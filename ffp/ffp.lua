local function opencomputers(func, ...)
  if os.sleep then
    return func(...)
  end
  return nil
end

local function standalone(func, ...)
  if not os.sleep then
    return func(...)
  end
  return nil
end

local component = opencomputers(require, "component")
local fs = opencomputers(require, "filesystem")
local shell = opencomputers(require, "shell")
local term = opencomputers(require, "term")
local unicode = opencomputers(require, "unicode")

local complex = require("complex")

local gpu = opencomputers(function() return component.gpu end)

local function reverseBits(num, bitlen)
  local result = 0
  local n = 1 << bitlen
  local nrev = num
  for i = 1, bitlen - 1, 1 do
    num = num >> 1
    nrev = nrev << 1
    nrev = nrev | (num & 1)
  end
  nrev = nrev & (n - 1)
  return nrev
end

local function fft(x)
  local bitlen = math.ceil(math.log(#x, 2))
  local data = {}
  for i = 0, #x, 1 do
    data[reverseBits(i, bitlen)] = complex(x[i])
  end

  for s = 1, bitlen, 1 do
    local m = 2^s
    local hm = m * 0.5
    local omegaM = (complex{0, -2 * math.pi / m}):exp()
    for k = 0, #x, m do
      local omega = complex(1)
      for j = 0, hm - 1 do
        local t = omega * data[k + j + hm]
        local u = data[k + j]
        data[k + j] = u + t
        data[k + j + hm] = u - t
        omega = omega * omegaM
      end
    end
  end
  return data
end

local log = os.sleep and io.stdout or io.stderr

local function clearLine()
  if os.sleep then
    term.clearLine()
  else
    log:write("\027[2K\027[1G")
  end
end

local args, options = table.pack(...), {}
opencomputers(function()
  args, options = shell.parse(table.unpack(args))
end)

local chans = {}

local path, depth, rate, sampleSize, step, len

if options.l or options.load then
  path, len = table.unpack(args)
  if not path then
    io.stderr:write("Usage: ffp <path> [len]\n")
    return
  end
  local f = io.open(path, "rb")

  depth, rate, sampleSize, step = (">nnnn"):unpack(f:read(8 * 4))
  local cur = 32
  local total = f:seek("end") - 32
  f:seek("set", cur)

  -- 1 second byte length = (sample rate / sampleSize)
  --                      × number size (8 bytes)
  --                      × 8 channels
  --                      × 2 numbers (frequency and amplitude)
  len = tonumber(len) or total / rate / 8 / 8 / 2 * sampleSize
  total = math.min(total, len * rate * 8 * 8 / sampleSize * 2)
  log:write("Loading " .. math.floor(total) .. " B of " .. path .. "\n")
  for i = 1, total, 8 do
    chans[#chans + 1] = (">n"):unpack(f:read(8))
  end
else
  path, depth, rate, sampleSize, step, len = table.unpack(args)
  if not (path and depth and rate) then
    io.stderr:write("Usage: ffp <path> <depth> <sample rate> [sample size] [sample step] [len]\n")
    return
  end
  depth, rate = tonumber(depth), tonumber(rate)
  sampleSize = tonumber(sampleSize) or 1024
  step = tonumber(step) or 1

  local f = io.open(path, "rb")
  local total = f:seek("end")
  f:seek("set")

  depth = math.floor(depth / 8)
  len = tonumber(len) or total / rate / depth

  total = math.min(total, len * rate * depth)

  sampleSize = 2^math.ceil(math.log(sampleSize, 2)) - 1
  step = math.floor((sampleSize + 1) / step + .5)

  log:write("Loading " .. ("%.2f"):format(len) .. "s of " .. path .. ": pcm_s" .. (depth * 8) .. (depth > 1 and "le" or "") .. " @ " .. rate .. " Hz [" .. math.floor(sampleSize + 1) .. " samples -> " .. math.floor(step) .. "]\n")
  standalone(function()
    io.stdout:write((">nnnn"):pack(depth, rate, sampleSize, step))
  end)

  local iTime = os.clock()
  local startTime = iTime

  opencomputers(os.sleep, 0)
  local lastSleep = os.clock()

  local shift = 0

  local content = standalone(f.read, f, "*a")
  local bufpos = 1

  local function read(l)
    if os.sleep then
      return f:read(l)
    end
    local data = content:sub(bufpos, bufpos + l - 1)
    bufpos = bufpos + l
    return data
  end

  while shift < total do
    local samples = {}
    for i = 1, math.min(sampleSize, total - shift) * depth, depth do
      local sample = read(depth)
      sample = ("<i" .. depth):unpack(sample)
      samples[#samples + 1] = sample / (2^(depth * 8) / 2)
    end

    local requiredLen = 2^math.ceil(math.log(#samples, 2))
    for i = #samples, requiredLen - 1, 1 do
      table.insert(samples, 0)
    end

    for i = 1, #samples, 1 do
      samples[i - 1] = samples[i]
    end

    samples[#samples] = nil

    result = fft(samples, true)

    for i = 1, #result, 1 do
      result[i] = {i * rate / (#result + 1), result[i]:abs() / (#result + 1), select(2, result[i]:polar())}
    end

    for i = #result, 1, -1 do
      result[i + 1] = result[i]
    end

    for i = math.floor(#result / 2), #result, 1 do
      result[i] = nil
    end

    table.sort(result, function(lhs, rhs)
      return lhs[2] > rhs[2]
    end)

    for i = 1, 8, 1 do
      table.insert(chans, result[i][1])
      table.insert(chans, result[i][2])
    end

    if total - shift < sampleSize then
      break
    end
    shift = shift + step * depth
    clearLine()
    local dig = math.ceil(math.log(total, 10))
    log:write(("%" .. dig .. ".0f B processed out of %" .. dig .. ".0f B (took %.3fs)"):format(shift, total, os.clock() - iTime))
    iTime = os.clock()
    opencomputers(function()
      if os.clock() - lastSleep > 2.5 then
        os.sleep(0)
        lastSleep = os.clock()
      end
    end)
  end

  f:close()

  clearLine()
  log:write(("%.0f B processed for %.3fs (%.2f B/s)\n"):format(total, os.clock() - startTime, total / (os.clock() - startTime)))
end

opencomputers(function()
  local maxAmplitude = 0
  for i = 2, #chans, 2 do
    maxAmplitude = math.max(maxAmplitude, chans[i])
  end

  local iteration = 1

  local delay = 0

  local s = component.sound
  local sleep = step / rate

  local lastSleep = os.clock()

  for sample = 1, #chans, 8 * 2 do
    clearLine()
    log:write(("Playing: %.2fs/%.2fs (%3.0f%%)"):format(iteration * sleep, len, iteration * sleep / len * 100))
    local i = 1
    for chan = sample, sample + 8 * 2 - 1, 2 do
      s.setWave(i, s.modes.sine)
      s.setFrequency(i, chans[chan])
      s.setVolume(i, chans[chan + 1] / maxAmplitude)
      s.open(i)
      i = i + 1
    end
    s.delay(math.floor(sleep * 1000))
    delay = delay + math.floor(sleep * 1000)
    if delay > 100 then
      s.process()
      os.sleep(0.1)
      s.process()
      delay = 0
    end
    iteration = iteration + 1
  end

  while not s.process() do
    os.sleep(0.1)
  end

  print("\n\nExiting")
end)

standalone(function()
  for k, v in pairs(chans) do
    chans[k] = (">n"):pack(v)
  end
  io.stdout:write(table.concat(chans, ""))
end)
