# MacSE30
Minimal 68030 &amp; 68882 accelerator card for the Macintosh SE

This project is not intended to be the fastest or most feature-rich accelerator for the Mac SE. Its primary goal is to be simple and transparent to Mac OS. Without the FPU, it should be able to function as just a faster Mac SE. To make full use of the FPU and the 68030's onboard cache, MacOS may need an init or extension to enable these features and advertise their presence to applications. 

The glue logic is entirely contained in a single 64-macrocel CPLD. Either an Altera EPM7064 or an Atmel ATF1504 will work. It is programmed and compiled for the Altera chip, but tested with the Atmel chip, using the free POF2JED software to convert the compiled configuration to the Atmel format. 

Should the initial design prove successful, future revisions may add cache or RAM on a 32-bit bus to further accelerate the SE. 