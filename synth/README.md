# synth
*An easy-to-use interface to the sound card.*

Available for downloading on the [Hel Repository](https://hel.fomalhaut.me/#packages/synth).

### Libraries
This program uses a lot of libraries written by other people.

* `GUI.lua`, a wonderful GUI library written by @IgorTimofeev.
  * `advancedLua.lua`
  * `color.lua` -- modified by me to work on Lua 5.3
  * `image.lua` -- stripped the depenedncy on OCIF as I don't need it
* `doubleBuffering.lua`, a library; provides a buffer that, when flushed, tries to use as less draw instructions as possible, drawing complex things really fast. Also written by @IgorTimofeev.
* A bundled beautiful plotter library written by @LeshaInc; also modified by me: it now actually works and uses the doubleBuffering library.

![Screenshot](https://i.imgur.com/Ahxvlv2.png)

## License
This program uses the Apache 2.0 license. The text of the license can be obtained [here](http://www.apache.org/licenses/LICENSE-2.0).
