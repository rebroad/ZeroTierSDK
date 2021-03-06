#
# Makefile for ZeroTier SDK on Linux
#
# Targets
#   all: build every target possible on host system, plus tests
#   check: reports OK/FAIL of built targets
#   tests: build only test applications for host system
#   clean: removes all built files, objects, other trash

# Automagically pick clang or gcc, with preference for clang
# This is only done if we have not overridden these with an environment or CLI variable
ifeq ($(origin CC),default)
	CC=$(shell if [ -e /usr/bin/clang ]; then echo clang; else echo gcc; fi)
endif
ifeq ($(origin CXX),default)
	CXX=$(shell if [ -e /usr/bin/clang++ ]; then echo clang++; else echo g++; fi)
endif

#UNAME_M=$(shell $(CC) -dumpmachine | cut -d '-' -f 1)

INCLUDES?=
DEFS?=
LDLIBS?=

include objects.mk

ifeq ($(ZT_DEBUG),1)
	DEFS+=-DZT_TRACE
	CFLAGS+=-Wall -g -pthread $(INCLUDES) $(DEFS)
	CXXFLAGS+=-Wall -g -pthread $(INCLUDES) $(DEFS)
	LDFLAGS=-ldl
	STRIP?=echo
	# The following line enables optimization for the crypto code, since
	# C25519 in particular is almost UNUSABLE in -O0 even on a 3ghz box!
ext/lz4/lz4.o node/Salsa20.o node/SHA512.o node/C25519.o node/Poly1305.o: CFLAGS = -Wall -O2 -g -pthread $(INCLUDES) $(DEFS)
else
	CFLAGS?=-O3 -fstack-protector
	CFLAGS+=-Wall -fPIE -fvisibility=hidden -pthread $(INCLUDES) -DNDEBUG $(DEFS)
	CXXFLAGS?= -fstack-protector
	CXXFLAGS+=-Wall -Wreorder -fPIE -fvisibility=hidden -fno-rtti -pthread $(INCLUDES) -DNDEBUG $(DEFS)
	LDFLAGS=-ldl -pie -Wl,-z,relro,-z,now
	STRIP?=strip
	STRIP+=--strip-all
endif

# Debug output for ZeroTier service
ifeq ($(ZT_TRACE),1)
	DEFS+=-DZT_TRACE
endif

# Debug output for lwIP
ifeq ($(SDK_LWIP_DEBUG),1)
	LWIP_FLAGS:=SDK_LWIP_DEBUG=1
endif

# Debug output for the SDK
# Specific levels can be controlled in src/SDK_Debug.h
ifeq ($(SDK_DEBUG),1)
	DEFS+=-DSDK_DEBUG -g
endif
# Log debug chatter to file, path is determined by environment variable ZT_SDK_LOGFILE
ifeq ($(SDK_DEBUG_LOG_TO_FILE),1)
	DEFS+=-DSDK_DEBUG_LOG_TO_FILE
endif


# Target output filenames
SHARED_LIB_NAME    = libztlinux.so
INTERCEPT_NAME     = libztintercept.so
SDK_SERVICE_NAME   = zerotier-sdk-service
ONE_SERVICE_NAME   = zerotier-one
ONE_CLI_NAME       = zerotier-cli
ONE_ID_TOOL_NAME   = zerotier-idtool
LWIP_LIB_NAME      = liblwip.so
#
SHARED_LIB         = $(BUILD)/$(SHARED_LIB_NAME)
INTERCEPT          = $(BUILD)/$(INTERCEPT_NAME)
SDK_SERVICE        = $(BUILD)/$(SDK_SERVICE_NAME)
ONE_SERVICE        = $(BUILD)/$(ONE_SERVICE_NAME)
ONE_CLI            = $(BUILD)/$(ONE_CLI_NAME)
ONE_IDTOOL         = $(BUILD)/$(ONE_IDTOOL_NAME)
LWIP_LIB           = $(BUILD)/$(LWIP_LIB_NAME)

all: remove_only_intermediates linux_shared_lib check

remove_only_intermediates:
	-find . -type f \( -name '*.o' -o -name '*.so' \) -delete




# --- EXTERNAL LIBRARIES ---
lwip:
	make -f make-liblwip.mk $(LWIP_FLAGS)




# --------- LINUX ----------
# Build everything
linux: one linux_service_and_intercept linux_shared_lib

# Build vanilla ZeroTier One binary
one: $(OBJS) $(ZT1)/service/OneService.o $(ZT1)/one.o $(ZT1)/osdep/LinuxEthernetTap.o
	mkdir -p $(BUILD)
	$(CXX) $(CXXFLAGS) $(LDFLAGS) -o $(BUILD)/zerotier-one $(OBJS) $(ZT1)/service/OneService.o $(ZT1)/one.o $(ZT1)/osdep/LinuxEthernetTap.o $(LDLIBS)
	$(STRIP) $(ONE_SERVICE)
	cp $(ONE_SERVICE) $(INT)/docker/docker_demo/$(ONE_SERVICE_NAME)

# Build only the intercept library
linux_intercept:
	# Use gcc not clang to build standalone intercept library since gcc is typically used for libc and we want to ensure maximal ABI compatibility
	cd src ; gcc $(DEFS) -O2 -Wall -std=c99 -fPIC -DVERBOSE -D_GNU_SOURCE -DSDK_INTERCEPT -I. -I../$(ZT1)/node -nostdlib -shared -o ../$(INTERCEPT) SDK_Sockets.c SDK_Intercept.c SDK_Debug.c SDK_RPC.c -ldl

# Build only the SDK service
linux_sdk_service: lwip $(OBJS)
	mkdir -p $(BUILD)/linux_intercept
	$(CXX) $(CXXFLAGS) $(LDFLAGS) $(DEFS) -DSDK -DZT_ONE_NO_ROOT_CHECK -Iext/lwip/src/include -Iext/lwip/src/include/ipv4 -Iext/lwip/src/include/ipv6 -I$(ZT1)/osdep -I$(ZT1)/node -Isrc -o $(SDK_SERVICE) $(OBJS) $(ZT1)/service/OneService.cpp src/SDK_EthernetTap.cpp src/SDK_Proxy.cpp $(ZT1)/one.cpp -x c src/SDK_RPC.c $(LDLIBS) -ldl
	ln -sf $(SDK_SERVICE_NAME) $(BUILD)/zerotier-cli
	ln -sf $(SDK_SERVICE_NAME) $(BUILD)/zerotier-idtool

# Build both intercept library and SDK service (separate)
linux_service_and_intercept: linux_intercept linux_sdk_service
	
# Builds a single shared library which contains everything
linux_shared_lib: $(OBJS)
	$(CXX) $(CXXFLAGS) $(LDFLAGS) -DSDK -DZT_ONE_NO_ROOT_CHECK -Iext/lwip/src/include -Iext/lwip/src/include/ipv4 -Iext/lwip/src/include/ipv6 -Izerotierone/osdep -Izerotierone/node -Izerotierone/service -Isrc -shared -o $(SHARED_LIB) $(OBJS) zerotierone/service/OneService.cpp src/SDK_Service.cpp src/SDK_EthernetTap.cpp src/SDK_Proxy.cpp zerotierone/one.cpp -x c src/SDK_Sockets.c src/SDK_Intercept.c src/SDK_Debug.c src/SDK_RPC.c $(LDLIBS) -ldl




# -------- ANDROID ---------
# TODO: CHECK if ANDROID/GRADLE TOOLS are installed
# Build library for Android Unity integrations
# Build JNI library for Android app integration
android_jni_lib:
	cd $(INT)/android/android_jni_lib/proj; ./gradlew assembleDebug
	mkdir -p $(BUILD)/android_jni_lib
	cp docs/android_zt_sdk.md $(BUILD)/android_jni_lib/README.md
	mv -f $(INT)/android/android_jni_lib/java/libs/* $(BUILD)/android_jni_lib
	cp -R $(BUILD)/android_jni_lib/* $(INT)/android/example_app/app/src/main/jniLibs




# -------- TESTING ---------
# Build the docker demo images
docker_demo: one linux_shared_lib
	mkdir -p $(BUILD)
	cp $(INTERCEPT) $(INT)/docker/docker_demo/$(INTERCEPT_NAME)
	cp $(SERVICE) $(INT)/docker/docker_demo/$(SERVICE_NAME)
	cp $(LWIP_LIB) $(INT)/docker/docker_demo/$(LWIP_LIB_NAME)
	cp $(ONE_CLI) $(INT)/docker/docker_demo/$(ONE_CLI_NAME)
	touch $(INT)/docker/docker_demo/docker_demo.name
	# Server image
	# This image will contain the server application and everything required to 
	# run the ZeroTier SDK service
	cd $(INT)/docker/docker_demo; docker build --tag="docker_demo" -f sdk_dockerfile .
	# Client image
	# This image is merely a test image designed to interact with the server image
	# in order to verify it's working properly
	cd $(INT)/docker/docker_demo; docker build --tag="docker_demo_monitor" -f monitor_dockerfile .

# Builds all docker test images
docker_images: one linux_shared_lib
	./tests/docker/build_images.sh

# Runs docker container tests
docker_test:
	./tests/docker/test.sh

# Checks the results of the docker tests
docker_check_test:
	./tests/docker/check.sh

# Check for the presence of built frameworks/bundles/libaries
check:
	./check.sh $(LWIP_LIB)
	./check.sh $(INTERCEPT)
	./check.sh $(ONE_SERVICE)
	./check.sh $(SDK_SERVICE)
	./check.sh $(SHARED_LIB)
	./check.sh $(BUILD)/android_jni_lib/arm64-v8a/libZeroTierOneJNI.so
	./check.sh $(BUILD)/android_jni_lib/armeabi/libZeroTierOneJNI.so
	./check.sh $(BUILD)/android_jni_lib/armeabi-v7a/libZeroTierOneJNI.so
	./check.sh $(BUILD)/android_jni_lib/mips/libZeroTierOneJNI.so
	./check.sh $(BUILD)/android_jni_lib/mips64/libZeroTierOneJNI.so
	./check.sh $(BUILD)/android_jni_lib/x86/libZeroTierOneJNI.so
	./check.sh $(BUILD)/android_jni_lib/x86_64/libZeroTierOneJNI.so

# Tests
TEST_OBJDIR := $(BUILD)/tests
TEST_SOURCES := $(wildcard tests/api_test/*.c)
TEST_TARGETS := $(addprefix $(BUILD)/tests/$(OSTYPE).,$(notdir $(TEST_SOURCES:.c=.out)))

$(BUILD)/tests/$(OSTYPE).%.out: tests/api_test/%.c
	-$(CC) $(CC_FLAGS) -o $@ $<

$(TEST_OBJDIR):
	mkdir -p $(TEST_OBJDIR)

tests: $(TEST_OBJDIR) $(TEST_TARGETS) linux_service_and_intercept
	mkdir -p $(BUILD)/tests; 
	mkdir -p build/tests/zerotier
	cp tests/api_test/test.sh $(BUILD)/tests/test.sh
	cp tests/api_test/servers.sh $(BUILD)/tests/servers.sh
	cp tests/api_test/clients.sh $(BUILD)/tests/clients.sh
	cp tests/cleanup.sh $(BUILD)/tests/cleanup.sh
	cp $(LWIP_LIB) $(BUILD)/tests/zerotier/liblwip.so



# ----- ADMINISTRATIVE -----
clean_android:
	# android JNI lib project
	-test -s /usr/bin/javac || { echo "Javac not found"; exit 1; }
	-cd $(INT)/android/android_jni_lib/proj; ./gradlew clean
	-rm -rf $(INT)/android/android_jni_lib/proj/build
	# example android app project
	-cd $(INT)/android/example_app; ./gradlew clean

clean_basic:
	-rm -rf $(BUILD)/*
	-rm -rf $(INT)/Unity3D/Assets/Plugins/*
	-rm -rf zerotier-cli zerotier-idtool
	-find . -type f \( -name $(ONE_SERVICE_NAME) -o -name $(SDK_SERVICE_NAME) \) -delete
	-find . -type f \( -name '*.o' -o -name '*.so' -o -name '*.o.d' -o -name '*.out' -o -name '*.log' -o -name '*.dSYM' \) -delete

clean: clean_basic clean_android

clean_for_production:
	-find . -type f \( -name '*.identity'\) -delete
