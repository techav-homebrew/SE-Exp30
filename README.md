# SE-Exp30 Mac SE Accelerator
Minimal 68030 &amp; 68882 accelerator card for the Macintosh SE

This project is not intended to be the fastest or most feature-rich accelerator for the Mac SE. Its primary goal is to be simple and transparent to Mac OS. Without the FPU, it should be able to function as just a faster Mac SE. To make full use of the FPU and the 68030's onboard cache, MacOS may need an init or extension to enable these features and advertise their presence to applications. 

The glue logic is entirely contained in a single 64-macrocel CPLD. Either an Altera EPM7064 or an Atmel ATF1504 will work. It is programmed and compiled for the Altera chip, but tested with the Atmel chip, using the free POF2JED software to convert the compiled configuration to the Atmel format. 

Should the initial design prove successful, future revisions may add cache or RAM on a 32-bit bus to further accelerate the SE. 

## Bill of Materials
Parts count is minimal
- Motorola 68030 CPU (MC68030RC or MC68030RP)
- Motorola 68882 FPU (MC68882RC)
- Microchip/Atmel ATF1504AS-10JU84 (PLLC-84)
- 7x 74'245 buffers (SOIC-20)
- 2x 10uF Electrolyic capacitors (5mm, 2.5mm lead spacing)
- 33x 1uF Ceramic capacitors (0805)
- 16x 4k7 resistors (0805)
- TTL Crystal Oscillator (DIP-8)
- DIN 41612-C 96-pin right-angle connector (male)
- optional 4-pin floppy/Berg power connector

None of the part values are especially critical. The oscillator frequency should match the intended CPU/FPU speed, and the speed grade for the CPLD should be appropriate for the target speed as well. Timing for the CPLD was planned with a 10ns CPLD and 50MHz CPU in mind. As the 68030 CPU and 68882 FPU are no longer produced, it is left to the reader to source these parts and determine the appropriate oscillator frequency to use with whatever parts are available. Processors were originally offered in 16MHz, 20MHz, 25MHz, 33MHz, 40MHz, and 50MHz ratings. It may be necessary to convert the PCB to 4-layers and insert internal power/ground planes to achieve higher clock rates. 

All capacitors on the BOM are included for bypass/filter purposes, so their values are not critical. Lower capacitance isn't recommended, but higher values may certainly be substituted. Similarly, the resistors only serve as pull-ups so their values are also not critical. 

## Power Supply
The Mac SE is rated to provide 7.5W on the 5V rail for PDS cards. This card may exceed that 7.5W rating. Depending on the configuration of the SE model (e.g. presence of a hard drive) and the health of the power supply, a separate 5V power supply may be necessary to power this accelerator. A footprint is provided for a 4-pin floppy (Berg) connector. If an external power supply is used, the jumpers J1, J2, J3 should be left open. If the card will be powered via the PDS slot, these jumpers should be closed, and nothing should be connected to the power connector. 