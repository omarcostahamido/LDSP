# Example Usage:
#  export TOOLCHAIN_PATH=/opt/homebrew/share/android-ndk/toolchains/llvm/prebuilt/darwin-x86_64
#  make VENDOR=Huawei MODEL="P8 Lite (alice)" ANDROID_VERSION=7.0 PROJECT=examples/backlight_sine


# === Command-Line Parameters ===

# TOOLCHAIN_PATH: The path to the Android NDK toolchain
ifdef TOOLCHAIN_PATH
require_toolchain: ;
else
require_toolchain:
	$(error TOOLCHAIN_PATH is not set)
endif

# VENDOR: The vendor of the phone (e.g. LG, Huawei)
# MODEL: The specific model of the phone (e.g. G2 Mini (g2m), P8 Lite (alice))
ifdef VENDOR
ifdef MODEL
require_model: ;
else
require_model:
	$(error MODEL is not set)
endif
else
require_model:
	$(error VENDOR is not set)
endif

# ANDROID_VERSION: The full, human-readable Android version of the phone, e.g. 5.1.1 or 7.0
# This is used to determine the API level of the phone
ifdef ANDROID_VERSION
require_android_version: ;
else
require_android_version:
	$(error ANDROID_VERSION is not set)
endif

# PROJECT: The path to the user's LDSP project which is currently being compiled
# e.g. examples/hello_world
ifdef PROJECT
require_project: ;
else
require_project:
	$(error PROJECT is not set)
endif

# === Build ===

ifdef VENDOR
ifdef MODEL
# Path to the LDSP hardware configuration definition
# This file stores information about the phone's processor and other hardware
HW_CONFIG := ./phones/$(VENDOR)/$(MODEL)/ldsp_hw_config.json

# Target Architecture
# The CPU architecture of the phone (e.g. armv7a, aarch64)
ARCH_FULL := $(shell grep 'target architecture' "$(HW_CONFIG)" | cut -d \" -f 4)

# The architecture family used by the toolchain
# ARCH_SHORT one of "arm", "aarch64", "i686", "x86_64"
# EABI is either "" or the string "eabi" and defines the
# application binary interface used by the toolchain
ifneq (,$(findstring arm,$(ARCH_FULL)))
	ARCH_SHORT := arm
	EABI := eabi
else
	ARCH_SHORT := $(ARCH_FULL)
	EABI :=
endif

# Whether the phone has a NEON floating point unit,
# which can be used to speed up float operations
NEON_SUPPORT := $(shell grep 'supports neon floating point unit' "$(HW_CONFIG)" | cut -d \" -f 4)

# This is where compiled parts of the LDSP library are stored
# Caching these speeds up subsequent builds, but different phones
# may require different versions of the library
OBJECT_DIR := ./obj/$(VENDOR)/$(MODEL)

# We can't use quotes to escape makefile rule names, so we backslash-escape all the spaces
OBJECT_DIR_ESCAPED := $(subst $() ,\ ,$(OBJECT_DIR))

endif # ifdef MODEL
endif # ifdef VENDOR

ifdef ANDROID_VERSION

# The three components of the Android version (x.y.z)
ANDROID_MAJOR := $(shell echo $(ANDROID_VERSION) | cut -d . -f 1)
ANDROID_MINOR := $(shell echo $(ANDROID_VERSION) | cut -d . -f 2)
ANDROID_PATCH := $(shell echo $(ANDROID_VERSION) | cut -d . -f 3)

include ./android-versions.mk

$(info Detected Android API level $(API_LEVEL))

# The compilation target, determined by the phone's architecture and API level
TARGET := $(ARCH_FULL)-linux-android$(EABI)$(API_LEVEL)

ifeq ($(ARCH_FULL),aarch64) # aarch64 had neon active by default, no need to set flag
	NEON :=
else ifneq (,$(findstring $(NEON_SUPPORT), true yes 1 True Yes))
	NEON := -mfpu=neon-fp16
endif

endif # ifdef ANDROID_VERSION

ifdef TOOLCHAIN_PATH

# The path to the C and C++ compilers used
CC := $(TOOLCHAIN_PATH)/bin/clang
CXX := $(TOOLCHAIN_PATH)/bin/clang++

# The path to the Android API libraries for the phone's API level
ANDROID_LIB_PATH := $(TOOLCHAIN_PATH)/sysroot/usr/lib/$(ARCH_SHORT)-linux-android$(EABI)/$(API_LEVEL)

endif # ifdef TOOLCHAIN_PATH

# Includes used by the LDSP library and the user's project
INCLUDES := -I./include -I./libraries/tinyalsa/include -I./libraries -I.
# Flags for the compiler to link against required libraries
LIBRARIES := -lm -landroid -static-libstdc++ -L$(ANDROID_LIB_PATH)
# Sources for .c and .cpp files in the LDSP library
CSOURCES := $(wildcard core/*.c) $(wildcard libraries/*/*.c) $(wildcard libraries/*/*/*.c)
CPPSOURCES := $(wildcard core/*.cpp) $(wildcard libraries/*/*.cpp) $(wildcard libraries/*/*/*.cpp)

# All of the makefile rules required to build the LDSP library
# We define OBJECT_RULES with the escaping needed to reference the .o makefile rules
# i.e., spaces backslash-escaped, parens not escaped
OBJECT_RULES := $(addprefix $(OBJECT_DIR_ESCAPED)/, $(CSOURCES:.c=.o) $(CPPSOURCES:.cpp=.o))

# We define OBJECT_PATHS with the escaping needed to pass the list of .o files to the linker
# i.e., each path surrounded by quotes, no other escaping done
OBJECT_PATHS := $(addprefix "$(OBJECT_DIR)/, $(addsuffix ", $(CSOURCES:.c=.o) $(CPPSOURCES:.cpp=.o)))

# The path to where the compiled executable will be stored
BUILD_DIR := $(PROJECT)/bin/$(VENDOR)/$(MODEL)

# The directory where object files for the user's project are stored
PROJECT_OBJECT_DIR := $(PROJECT)/obj/$(VENDOR)/$(MODEL)
PROJECT_OBJECT_DIR_ESCAPED := $(subst $() ,\ ,$(PROJECT_OBJECT_DIR))

# Sources for .c and .cpp files in the user's project
PROJECT_CSOURCES := $(wildcard $(PROJECT)/*.c) $(wildcard $(PROJECT)/*/*.c) $(wildcard $(PROJECT)/*/*/*.c)
PROJECT_CPPSOURCES := $(wildcard $(PROJECT)/*.cpp) $(wildcard $(PROJECT)/*/*.cpp) $(wildcard $(PROJECT)/*/*/*.cpp)

# The relative path to all of the .o files required to build the user's project
PROJECT_OBJECTS := $(PROJECT_CSOURCES:$(PROJECT)/%.c=%.o) $(PROJECT_CPPSOURCES:$(PROJECT)/%.cpp=%.o)

PROJECT_OBJECT_RULES := $(addprefix $(PROJECT_OBJECT_DIR_ESCAPED)/, $(PROJECT_OBJECTS))
PROJECT_OBJECT_PATHS := $(addprefix "$(PROJECT_OBJECT_DIR)/, $(addsuffix ", $(PROJECT_OBJECTS)))

# Compiler Flags
CCFLAGS := -target $(TARGET) $(NEON) -ffast-math
CPPFLAGS := $(INCLUDES) -DAPI_LEVEL="$(API_LEVEL)"
CXXFLAGS := -target $(TARGET) $(NEON) -ffast-math

# We can't use $(dir ...) because it splits on spaces (even escaped ones :/)
# so we use `dirname` instead in the following rules

# .c files within LDSP itself
$(OBJECT_DIR_ESCAPED)/%.o: %.c
	@mkdir -p "$(shell dirname "$@")"
	$(CC) $(CPPFLAGS) $(CCFLAGS) -c "$^" -o "$@"

# .cpp files within LDSP itself
$(OBJECT_DIR_ESCAPED)/%.o: %.cpp
	@mkdir -p "$(shell dirname "$@")"
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -c "$^" -o "$@"

# .c files within the user's project
$(PROJECT_OBJECT_DIR_ESCAPED)/%.o: $(PROJECT)/%.c
	@mkdir -p "$(shell dirname "$@")"
	$(CC) $(CPPFLAGS) $(CCFLAGS) -c "$^" -o "$@"

# .cpp files within the user's project
$(PROJECT_OBJECT_DIR_ESCAPED)/%.o: $(PROJECT)/%.cpp
	@mkdir -p "$(shell dirname "$@")"
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -c "$^" -o "$@"

# Build the LDSP library and the user's project
build: require_toolchain require_model require_android_version require_project $(OBJECT_RULES) $(PROJECT_OBJECT_RULES)
	@mkdir  -p "$(BUILD_DIR)"
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -o "$(BUILD_DIR)/ldsp" $(OBJECT_PATHS) $(PROJECT_OBJECT_PATHS) $(LIBRARIES)

# === Push  ===

push: require_model require_project
	@adb root
	@adb push "$(HW_CONFIG)" /data/ldsp/ldsp_hw_config.json
	@adb push "$(BUILD_DIR)/ldsp" /data/ldsp/ldsp

push_shell: require_model require_project
	@adb push "$(HW_CONFIG)" /sdcard/ldsp/ldsp_hw_config.json
	@adb push "$(BUILD_DIR)/ldsp" /sdcard/ldsp/ldsp

# === Clean ===

clean: require_model require_project
	@rm -rf "$(BUILD_DIR)"
	@rm -rf "$(OBJECT_DIR)"
	@rm -rf "$(PROJECT_OBJECT_DIR)"

cleanProject: require_project
	@rm -rf "$(PROJECT)/bin"
	@rm -rf "$(PROJECT)/obj"

cleanAll:
	@rm -rf ./bin
	@rm -rf ./obj

run:
	adb shell "cd /data/ldsp/ && ./ldsp"

.PHONY: require_toolchain require_model require_android_version require_project build push push_shell clean cleanAll run
