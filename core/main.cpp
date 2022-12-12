// LineageDSP
#include <iostream>
#include <signal.h> //SIGINT, SIGTERM

#include "LDSP.h"
#include "hwConfig.h"
#include "commandLineArgs.h"
#include "mixer.h"
#include "outDevices.h"


using namespace std;


// Handle Ctrl-C by requesting that the audio rendering stop
void interrupt_handler(int sig)
{
	printf("--->Signal caught!<---\n");
	LDSP_requestStop();
}


//TODO move mixer setup/reset into audio calls
// and combine sensors and output calls into a single container file
// this will simplify a lot the default main file

int main(int argc, char** argv)
{
 	cout << "Hello!\n" << endl;

	LDSPinitSettings* settings = LDSP_InitSettings_alloc();	// Standard audio settings
	LDSP_defaultSettings(settings);

	if(LDSP_parseArguments(argc, argv, settings) < 0)
	{
		LDSP_InitSettings_free(settings);
		fprintf(stderr,"Error: unable to parse command line arguments\n");
		return 1;
	}

	LDSPhwConfig* hwconfig = LDSP_HwConfig_alloc();
	if(LDSP_parseHwConfigFile(settings, hwconfig)<0)
	{
		LDSP_HwConfig_free(hwconfig);
		LDSP_InitSettings_free(settings);
		fprintf(stderr,"Error: unable to parse hardwar configuration file\n");
	}

	if(LDSP_setMixerPaths(settings, hwconfig) < 0)
	{
		LDSP_HwConfig_free(hwconfig);
		LDSP_InitSettings_free(settings);
		fprintf(stderr,"Error: unable to set mixer paths\n");
		return 1;
	}

	if(LDSP_initOutDevices(settings, hwconfig) < 0)
	{
		LDSP_resetMixerPaths(hwconfig);
		LDSP_HwConfig_free(hwconfig);
		LDSP_InitSettings_free(settings);
		fprintf(stderr,"Error: unable to intialize output devices\n");
		return 1;
	}

	if(LDSP_initAudio(settings, 0) != 0) 
	{
		LDSP_cleanupOutDevices();
		LDSP_resetMixerPaths(hwconfig);
		LDSP_HwConfig_free(hwconfig);
		LDSP_InitSettings_free(settings);
		fprintf(stderr,"Error: unable to initialize audio\n");
		return 1;
	}

	LDSP_initSensors(settings);

	LDSP_InitSettings_free(settings);

	// Set up interrupt handler to catch Control-C and SIGTERM
	signal(SIGINT, interrupt_handler);
	signal(SIGTERM, interrupt_handler);

	// Start the audio device running
	if(LDSP_startAudio()) 
	{
		// Clean up any resources allocated
		LDSP_cleanupSensors();
	 	LDSP_cleanupAudio();
		LDSP_cleanupOutDevices();
		LDSP_resetMixerPaths(hwconfig);
		LDSP_HwConfig_free(hwconfig);
	 	return 1;
	}

	LDSP_cleanupSensors();

	LDSP_cleanupAudio();

	LDSP_resetMixerPaths(hwconfig);

	LDSP_cleanupOutDevices();

	LDSP_HwConfig_free(hwconfig);
	
	cout << "\nBye!" << endl;

	return 0;
}
