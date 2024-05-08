#!/bin/bash
# This script controls configuring the LDSP build system, building a project
# using LDSP, and running the resulting binary on a phone.

settings_file="ldsp_settings.conf" # this is created by this script via configure()
dependencies_file="ldsp_dependencies.conf" # this is created by CMake after build()

# Convert a human-readable Android version (e.g. 13, 6.0.1, 4.4) into an API level.
get_api_level () {
	version_major=$(echo $VERSION | cut -d . -f 1 )
	version_minor=$(echo $VERSION | cut -d . -f 2 )
	version_patch=$(echo $VERSION | cut -d . -f 3 )

	if [[ $version_major == 1 ]]; then
		if [[ $version_minor == 0 ]]; then
			level=1
		elif [[ $version_minor == 1 ]]; then
			level=2
		elif [[ $version_minor == 5 ]]; then
			level=3
		elif [[ $version_minor == 6 ]]; then
			level=4
		fi
	elif [[ $version_major == 2 ]]; then
		if [[ $version_minor == 0 ]]; then
			if [[ $version_patch == 1 ]]; then
				level=6
			else
				level=5
			fi
		elif [[ $version_minor == 1 ]]; then
			level=7
		elif [[ $version_minor == 2 ]]; then
			level=8
		elif [[ $version_minor == 3 ]]; then
			if [[ $version_patch == "" ]]; then
				level=9
			elif [[ $version_patch == 0 ]]; then
				level=9
			elif [[ $version_patch == 1 ]]; then
				level=9
			elif [[ $version_patch == 2 ]]; then
				level=9
			elif [[ $version_patch == 3 ]]; then
				level=10
			elif [[ $version_patch == 4 ]]; then
				level=10
			fi
		fi
	elif [[ $version_major == 3 ]]; then
		if [[ $version_minor == 0 ]]; then
			level=11
		elif [[ $version_minor == 1 ]]; then
			level=12
		elif [[ $version_minor == 2 ]]; then
			level=13
		fi
	elif [[ $version_major == 4 ]]; then
		if [[ $version_minor == 0 ]]; then
			if [[ $version_patch == "" ]]; then
				level=14
			elif [[ $version_patch == 0 ]]; then
				level=14
			elif [[ $version_patch == 1 ]]; then
				level=14
			elif [[ $version_patch == 2 ]]; then
				level=14
			elif [[ $version_patch == 3 ]]; then
				level=15
			elif [[ $version_patch == 4 ]]; then
				level=15
			fi
		elif [[ $version_minor == 1 ]]; then
			level=16
		elif [[ $version_minor == 2 ]]; then
			level=17
		elif [[ $version_minor == 3 ]]; then
			level=18
		elif [[ $version_minor == 4 ]]; then
			level=19
		fi
	# API_LEVEL 20 corresponds to Android 4.4W, which isn't relevant to us.
	elif [[ $version_major == 5 ]]; then
		if [[ $version_minor == 0 ]]; then
			level=21
		elif [[ $version_minor == 1 ]]; then
			level=22
		fi
	elif [[ $version_major == 6 ]]; then
		level=23
	elif [[ $version_major == 7 ]]; then
		if [[ $version_minor == 0 ]]; then
			level=24
		elif [[ $version_minor == 1 ]]; then
			level=25
		fi
	elif [[ $version_major == 8 ]]; then
		if [[ $version_minor == 0 ]]; then
			level=26
		elif [[ $version_minor == 1 ]]; then
			level=27
		fi
	elif [[ $version_major == 9 ]]; then
		level=28
	elif [[ $version_major == 10 ]]; then
		level=29
	elif [[ $version_major == 11 ]]; then
		level=30
	elif [[ $version_major == 12 ]]; then
	# Android 12 uses both API_LEVEL 31 and 32
	# Default to 31 but allow user to say "12.1" to get 32
		if [[ $version_minor == 1 ]]; then
			level=32
		else
			level=31
		fi
	elif [[ $version_major == 13 ]]; then
		level=33
	fi

  if [[ $level == "" ]]; then
    exit 1
  fi

	echo $level
}

# Retrieve the correct version of the onnxruntime library, based on Android version
get_onnx_version () {
  if [[ $api_level -ge 24 ]]; then 
    onnx_version="aboveOrEqual24"
  else 
    onnx_version="below24"
  fi

  echo $onnx_version
}

# Install the LDSP scripts on the phone.
install_scripts() {
  adb shell "su -c 'mkdir -p /sdcard/ldsp/scripts'" # create temp folder on sdcard
  adb push ./scripts/ldsp_* /sdcard/ldsp/scripts/ # push scripts there
  adb shell "su -c 'mkdir -p /data/ldsp/scripts'" # create ldsp scripts folder
  adb shell "su -c 'cp /sdcard/ldsp/scripts/* /data/ldsp/scripts'" # copy scripts to ldsp scripts folder
  adb shell "su -c 'rm -r /sdcard/ldsp'" # remove temp folder from sd card
}

# Configure the LDSP build system to build for the given phone model, Android version, and project path.
configure () {
  if [[ $VENDOR == "" ]]; then
    echo "Cannot configure: Vendor not specified"
    echo "Please specify a phone vendor with --vendor"
    exit 1
  fi
  vendor=$VENDOR

  if [[ $MODEL == "" ]]; then
    echo "Cannot configure: Model not specified"
    echo "Please specify a phone model with --model"
    exit 1
  fi
  model=$MODEL

  # path to hardware config
  hw_config="./phones/$vendor/$model/ldsp_hw_config.json"

  if [[ ! -f "$hw_config" ]]; then
    echo "Cannot configure: Hardware config file not found"
    echo "Please ensure that an ldsp_hw_config.json file exists for \"$vendor/$model\""
    exit 1
  fi

  # target ABI
  arch=$(grep 'target architecture' "$hw_config" | cut -d \" -f 4)
  if [[ $arch == "armv7a" ]]; then
    abi="armeabi-v7a"
  elif [[ $arch == "aarch64" ]]; then
    abi="arm64-v8a"
  elif [[ $arch == "x86" ]]; then
    abi="x86"
  elif [[ $arch == "x86_64" ]]; then
    abi="x86_64"
  else
    echo "Cannot configure: Unknown architecture: $arch"
    exit 1
  fi

  # target Android version
  api_level=$(get_api_level)
  exit_code=$?

  if [[ $exit_code != 0 ]]; then
    echo "Cannot configure: Unknown Android version: $VERSION"
    exit $exit_code
  fi

  # support for NEON floating-point unit
  explicit_neon="-DEXPLICIT_ARM_NEON=0"
  neon_setting=$(grep 'supports neon floating point unit' "$hw_config" | cut -d \" -f 4)
  if [[ $arch == "armv7a" ]];
  then
    if [[ $neon_setting =~ ^(true|True|yes|Yes|1)$ ]];
    then
      neon="-DANDROID_ARM_NEON=ON"
      explicit_neon="-DEXPLICIT_ARM_NEON=1"
    else
      neon=""
    fi
  else
    neon=""
  fi

  if [[ $PROJECT == "" ]]; then
    echo "Cannot configure: project path not specified"
    echo "Please specify a project path with --project"
    exit 1
  fi

  if [[ ! -d "$PROJECT" ]]; then
    echo "Cannot configure: project directory does not exist"
    echo "Please specify a valid project path with --project"
    exit 1
  fi
  project_dir=$PROJECT 
  project_name=$(basename "$project_dir")


  if [[ ! -d "$NDK" ]]; then
    echo "Cannot configure: NDK not found"
    echo "Please specify a valid NDK path with"
    echo "    export NDK=<path to NDK>"
    exit 1
  fi

  onnx_version=$(get_onnx_version)

  cmake -DCMAKE_TOOLCHAIN_FILE=$NDK/build/cmake/android.toolchain.cmake -DDEVICE_ARCH=$arch -DANDROID_ABI=$abi -DANDROID_PLATFORM=android-$api_level "-DANDROID_NDK=$NDK" $explicit_neon $neon "-DLDSP_PROJECT=$project_dir" "-DONNX_VERSION=$onnx_version" -G Ninja .
  exit_code=$?
  if [[ $exit_code != 0 ]]; then
    echo "Cannot configure: CMake failed"
    exit $exit_code
  fi

  # store settings
  echo "project_dir=\"$project_dir\"" > $settings_file
  echo "project_name=\"$project_name\"" >> $settings_file
  echo "vendor=\"$vendor\"" >> $settings_file
  echo "model=\"$model\"" >> $settings_file
  echo "arch=\"$arch\"" >> $settings_file
  echo "api_level=\"$api_level\"" >> $settings_file
  echo "onnx_version=\"$onnx_version\"" >> $settings_file
}

# Build the user project.
build () {
  if ! [[ -f $settings_file ]]; then
    echo "Cannot build: project not configured. Please run \"ldsp.sh configure [settings] first.\""
  fi

  ninja
  exit_code=$?
  if [[ $exit_code != 0 ]]; then
    echo "Cannot build: Ninja failed"
    exit $exit_code
  fi
}

# Clean the built files.
clean () {
  ninja clean
  rm $settings_file
  rm $dependencies_file
}

# Remove current project from directory from the device
clean_phone () {
  if ! [[ -f $settings_file ]]; then
    echo "Cannot clean phone: project not configured. Please run \"ldsp.sh configure [settings] first.\""
  fi

  # Retrieve variables from settings file
  if [[ -f $settings_file ]]; then
      source $settings_file
  fi

  adb shell "su -c 'rm -r /data/ldsp/projects/$project_name'" 
}

# Remove the ldsp directory from the device
clean_ldsp () {
  adb shell "su -c 'rm -r /data/ldsp/'" 
}



push_scripts() {
  adb shell "su -c 'mkdir -p /sdcard/ldsp/scripts'" # create temp folder on sdcard
  adb push ./scripts/ldsp_* /sdcard/ldsp/scripts/ # push scripts there
}

push_resources() {
  # push only if dependency is in use
  if [[ $ADD_SEASOCKS =~ ^(TRUE)$ ]]; then
    adb shell "su -c 'mkdir -p /sdcard/ldsp/resources'" # create temp folder on sdcard
    adb push resources /sdcard/ldsp/resources/  
  fi
}

push_onnxruntime() {
  # push only if dependency is in use
  if [[ $ADD_ONNX =~ ^(TRUE)$ ]]; then
    adb shell "su -c 'mkdir -p /sdcard/ldsp/onnxruntime'" # create temp folder on sdcard
    onnx_path="./dependencies/onnxruntime/$arch/$onnx_version/libonnxruntime.so"
    adb push $onnx_path /sdcard/ldsp/onnxruntime/libonnxruntime.so
  fi
}

# Install the user project, LDSP hardware config and resources to the phone.
install () {
  if [[ ! -f bin/ldsp ]]; then
    echo "Cannot install: no ldsp executable found. Please run \"ldsp.sh build\" first."
    exit 1
  fi
  
  # Retrieve variables from settings file
  if [[ -f $settings_file ]]; then
      source $settings_file
  fi

  # Retrieve variables from dependencies file
  if [[ -f $dependencies_file ]]; then
      source $dependencies_file
  fi


  hw_config="./phones/$vendor/$model/ldsp_hw_config.json"
  adb push "$hw_config" /sdcard/ldsp/projects/$project_name/ldsp_hw_config.json


  # Push all project resources, including Pd files in Pd projects, but excluding C/C++, assembly files and folders that contain those files
  # first folders
  find "$project_dir"/* -type d ! -exec sh -c 'ls -1q "{}"/*.cpp "{}"/*.c "{}"/*.h "{}"/*.hpp "{}"/*.S "{}"/*.s 2>/dev/null | grep -q . || echo "{}"' \; | xargs -I{} adb push {} /sdcard/ldsp/projects/$project_name
  # then files
  find "$project_dir" -maxdepth 1 -type f ! \( -name "*.cpp" -o -name "*.c" -o -name "*.h" -o -name "*.hpp" -o -name "*.S" -o -name "*.s" \) -exec adb push {} /sdcard/ldsp/projects/$project_name \;

  # now the ldsp bin
	adb push bin/ldsp /sdcard/ldsp/projects/$project_name/ldsp
  

  # now all resources that do not need to be updated at every build
  # first check if /data/ldsp exists
  if ! adb shell 'su -c "ls /data | grep ldsp"'; then
    # If /data/ldsp does not exist, create it
    adb shell 'su -c "mkdir -p /data/ldsp"'
    echo "/data/ldsp created. Pushing all necessary directories and files."

    # Call functions to push all resources
    push_scripts
    push_resources
    push_onnxruntime

  else
    # If /data/ldsp exists, continue with the checks
    # Check and push scripts if not there
    if ! adb shell 'su -c "ls /data/ldsp"' | grep "scripts"; then
      push_scripts
    fi

    # Check and push resources if not there
    if ! adb shell 'su -c "ls /data/ldsp"' | grep "resources"; then
      push_resources
    fi

    # Check and push onnxruntime if not there
    if ! adb shell 'su -c "ls /data/ldsp"' | grep "onnxruntime"; then
      push_onnxruntime
    fi
  fi

  
  adb shell "su -c 'mkdir -p /data/ldsp/projects/$project_name'" # create ldsp and project folders
  adb shell "su -c 'cp -r /sdcard/ldsp/* /data/ldsp'" # cp all files from sd card temp folder to ldsp folder
  adb shell "su -c 'chmod 777 /data/ldsp/projects/$project_name/ldsp'" # add exe flag to ldsp bin
  
  adb shell "su -c 'rm -r /sdcard/ldsp'" # remove the temp /sdcard/ldsp directory from the device
}

# Stop the currently-running user project on the phone.
stop () {
  echo "Stopping LDSP..."
  adb shell "su -c 'sh /data/ldsp/scripts/ldsp_stop.sh'"
}

handle_stop() {
  # Gracefully stop the LDSP process
  stop
  # Wait for the LDSP process and ADB shell to terminate properly
  sleep 1
}

# Run the user project on the phone.
run () {
  # Retrieve variables from settings file
  if [[ -f $settings_file ]]; then
      source $settings_file
  fi

  # Run adb shell in a subshell, so that it doesn't receive the SIGINT signal
  (
    trap "" INT
    adb shell "su -c 'cd /data/ldsp/projects/$project_name && export LD_LIBRARY_PATH="/data/ldsp/onnxruntime/" && ./ldsp $@'" # we invoke su before running the bin
  ) &


  # Trap the SIGINT signal in our "outer" shell so that we can gracefully
  # stop the LDSP process
  trap handle_stop INT

  # Wait for the subshell to terminate
  wait
}

# Run the user project on the phone in the background.
run_persistent () {
  # Retrieve variables from settings file
  if [[ -f $settings_file ]]; then
      source $settings_file
  fi

  cat <<EOF | adb shell > /dev/null 2>&1
  su -c '
  cd /data/ldsp/projects/$project_name
  nohup ./ldsp $@ > /dev/null 2>&1 &
  '
  exit
EOF
}

# Print usage information.
help () {
  echo -e "usage:"
  echo -e "ldsp.sh install_scripts"
  echo -e "ldsp.sh configure [settings]"
  echo -e "ldsp.sh build"
  echo -e "ldsp.sh install"
  echo -e "ldsp.sh run \"[list of arguments]\""
  echo -e "ldsp.sh stop"
  echo -e "ldsp.sh clean"
  echo -e "ldsp.sh clean_phone"
  echo -e "ldsp.sh clean_ldsp"
  echo -e "\nSettings (used with the 'configure' step):"
  echo -e "  --vendor=VENDOR, -v VENDOR\tThe vendor of the phone to build for."
  echo -e "  --model=MODEL, -m MODEL\tThe model of the phone to build for."
  echo -e "  --project=PROJECT, -p PROJECT\tThe path to the user project to build."
  echo -e "  --version=VERSION, -a VERSION\tThe Android version to build for."
  echo -e "\nDescription:"
  echo -e "  install_scripts\t\tInstall the LDSP scripts on the phone."
  echo -e "  configure\t\t\tConfigure the LDSP build system for the specified phone (vendor and model), version and project."
  echo -e "  \t\t\t\t(The above settings are needed)"
  echo -e "  build\t\t\t\tBuild the configured user project."
  echo -e "  install\t\t\t\tInstall the configured user project, LDSP hardware config, scripts and resources to the phone."
  echo -e "  run\t\t\t\tRun the configured user project on the phone."
  echo -e "  \t\t\t\t(Any arguments passed after \"run\" within quotes are passed to the user project)"
  echo -e "  stop\t\t\t\tStop the currently-running user project on the phone."
  echo -e "  clean\t\t\t\tClean the configured user project."
  echo -e "  clean_phone\t\t\tRemove all user project files from phone."
  echo -e "  clean_ldsp\t\t\tRemove all LDSP files from phone."
}

STEPS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --vendor=*)
      VENDOR="${1#*=}"
      shift
      ;;
    --vendor|-v)
      VENDOR="$2"
      shift
      shift
      ;;
    --model=*)
      MODEL="${1#*=}"
      shift
      ;;
    --model|-m)
      MODEL="$2"
      shift
      shift
      ;;
    --project=*)
      PROJECT="${1#*=}"
      shift
      ;;
    --project|-p)
      PROJECT="$2"
      shift
      shift
      ;;
    --version=*)
      VERSION="${1#*=}"
      shift
      ;;
    --version|-a)
      VERSION="$2"
      shift
      shift
      ;;
    --help|-h)
      STEPS+=("help")
      shift
      ;;
    -*|--*)
      echo "Unknown option $1"
      exit 1
      ;;
    run)
      # any arguments passed to "run" are passed to the user project
      STEPS+=("run")
      break
      ;;
      run_persistent)
      # any arguments passed to "run_persistent" are passed to the user project
      STEPS+=("run_persistent")
      break
      ;;
    *)
      STEPS+=("$1")
      shift
      ;;
  esac
done

if [ ${#STEPS[@]} -eq 0 ] ; then
  help
  exit 1
fi

for i in "${STEPS[@]}"; do
  case $i in
    install_scripts)
      install_scripts
      ;;
    configure)
      configure
      ;;
    build)
      build
      ;;
    clean)
      clean
      ;;
    clean_phone)
      clean_phone
      ;;
    clean_ldsp)
      clean_ldsp
      ;;
    install)
      install
      ;;
    install_scripts)
      install_scripts
      ;;
    run)
      run "${@:2}"
      ;;
    run_persistent)
      run_persistent "${@:2}"
      ;;
    stop)
      stop
      ;;
    help)
      help
      ;;
    *)
      echo "Unknown command $i"
      help
      exit 1
      ;;
  esac
done
