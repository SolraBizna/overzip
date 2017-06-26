This is a dangerous tool designed to make zipfiles smaller. It is only known to work on zipfiles created by the standard Info-ZIP `zip` program included with countless Unices.

It is written for Lua 5.2, but should work in 5.3 as well.

It primarily does two things:

- Stores filenames only once, in the central directory. The filename field in the local header will be empty.
- If multiple different files contain the same data, stores them only once.

This makes broken zipfiles that are horribly confusing to tools, and, in most cases, will not reduce size by much. It's mainly only useful if you have a lot of duplicate files inside a zipfile for some reason. Instead of using this tool to make that zipfile smaller, consider not having the duplicates in the first place.

Java's zipfile handling routines seem to accept these zipfiles without issue. Info-ZIP `unzip` prints many error messages, but unzips the files correctly.

This tool is in the public domain. Don't blame me if it breaks things.
