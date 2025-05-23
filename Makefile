SHELL = /bin/sh

.SUFFIXES:
.SUFFIXES: .o .c
.PHONY: all tests help README.build README.config simple default debug config menuconfig allyesconfig allnoconfig defconfig clean distclean

VER          := $(shell ./config.sh --ncam-version)
SVN_REV      := $(shell ./config.sh --ncam-revision)

uname_S := $(shell sh -c 'uname -s 2>/dev/null || echo not')

# This let's us use uname_S tests to detect cygwin
ifneq (,$(findstring CYGWIN,$(uname_S)))
	uname_S := Cygwin
endif

LINKER_VER_OPT:=-Wl,--version

# Find OSX SDK
ifeq ($(uname_S),Darwin)
	# Setting OSX_VER allows you to choose prefered version if you have
	# two SDKs installed. For example if you have 10.6 and 10.5 installed
	# you can choose 10.5 by using 'make USE_PCSC=1 OSX_VER=10.5'
	# './config.sh --detect-osx-sdk-version' returns the newest SDK if
	# SDK_VER is not set.
	OSX_SDK := $(shell ./config.sh --detect-osx-sdk-version $(OSX_VER))
	LINKER_VER_OPT:=-Wl,-v
endif

ifeq "$(shell ./config.sh --enabled WITH_SSL)" "Y"
	override USE_SSL=1
	override USE_LIBCRYPTO=1
endif
ifdef USE_SSL
	override USE_LIBCRYPTO=1
endif

CONF_DIR = /usr/local/etc

LIB_PTHREAD = -lpthread
LIB_DL :=

LIB_RT :=
ifeq ($(uname_S),Linux)
	LIB_DL := -ldl
ifndef ANDROID_NDK
	ifeq "$(shell ./config.sh --enabled CLOCKFIX)" "Y"
		LIB_RT := -lrt
	endif
endif
endif

override STD_LIBS := -lm $(LIB_PTHREAD) $(LIB_DL) $(LIB_RT)
override STD_DEFS := -D'CS_SVN_VERSION="$(SVN_REV)"'
ifneq "$(shell ./config.sh --git-revision)" ""
override STD_DEFS += -D'CS_GIT_VERSION="$(shell ./config.sh --git-revision | cut -d " " -f1-2 | sed -e "s| |:|g")"'
endif
override STD_DEFS += -D'CS_GIT_VERSION_HASH="$(shell ./config.sh --git-revision | cut -d " " -f3)"'
override STD_DEFS += -D'CS_CONFDIR="$(CONF_DIR)"'

ifdef ANDROID_NDK
	MODFLAGS_WARN = -Wno-strncat-size -Wno-implicit-function-declaration -Wno-unused-variable -Wno-unused-parameter -Wno-unused-function -Wno-format
else
	MODFLAGS_WARN = -Wno-shadow -Wno-implicit-function-declaration -Wno-unused-but-set-variable -Wno-unused-variable  -Wno-unused-parameter -Wno-unused-function -Wno-format
endif
MODFLAGS_OPTS = -fPIC -ffast-math -fwrapv -fomit-frame-pointer

# Compiler warnings
CC_WARN = -W -Wall -Wshadow -Wredundant-decls -Wstrict-prototypes -Wold-style-definition $(MODFLAGS_WARN)

# Compiler optimizations
CC_OPTS = -Os -ggdb -pipe -ffunction-sections -fdata-sections $(MODFLAGS_OPTS)

CC = $(CROSS_DIR)$(CROSS)gcc
STRIP = $(CROSS_DIR)$(CROSS)strip
LD = $(CROSS_DIR)$(CROSS)ld
OBJCOPY = $(CROSS_DIR)$(CROSS)objcopy

LDFLAGS += -Wl,--gc-sections

TARGETHELP := $(shell $(CC) --target-help 2>&1)
ifdef ANDROID_NDK
	override CFLAGS += -fPIE
else
	ifneq (,$(findstring sse2,$(TARGETHELP)))
		override CFLAGS += -fexpensive-optimizations -mmmx -msse -msse2 -msse3
	else
		override CFLAGS += -fexpensive-optimizations
	endif
endif

# The linker for powerpc have bug that prevents --gc-sections from working
# Check for the linker version and if it matches disable --gc-sections
# For more information about the bug see:
#   http://cygwin.com/ml/binutils/2005-01/msg00103.html
# The LD output is saved into variable and then processed, because if
# the output is piped directly into another command LD creates 4 files
# in your /tmp directory and doesn't delete them.
LINKER_VER := $(shell set -e; VER="`$(CC) $(LINKER_VER_OPT) 2>&1`"; echo $$VER | head -1 | cut -d' ' -f5)

# dm500 toolchain
ifeq "$(LINKER_VER)" "20040727"
	LDFLAGS :=
endif
# dm600/7000/7020 toolchain
ifeq "$(LINKER_VER)" "20041121"
	LDFLAGS :=
endif
# The OS X linker do not support --gc-sections
ifeq ($(uname_S),Darwin)
	LDFLAGS :=
endif

# The compiler knows for what target it compiles, so use this information
TARGET := $(shell $(CC) -dumpmachine 2>/dev/null)

# Process USE_ variables
ifdef USE_WI
override USE_STAPI=1
override CFLAGS += -DWITH_WI=1
override LDFLAGS += -DWITH_WI=1
DEFAULT_STAPI_LIB = -L./stapi -lwi
DEFAULT_STAPI_FLAGS = -I./stapi/include
else
DEFAULT_STAPI_LIB = -L./stapi -lncam_stapi
endif
DEFAULT_STAPI5_LIB = -L./stapi -lncam_stapi5
DEFAULT_COOLAPI_LIB = -lnxp -lrt
DEFAULT_COOLAPI2_LIB = -llnxUKAL -llnxcssUsr -llnxscsUsr -llnxnotifyqUsr -llnxplatUsr -lrt
DEFAULT_SU980_LIB = -lentropic -lrt
DEFAULT_AZBOX_LIB = -Lextapi/openxcas -lOpenXCASAPI
DEFAULT_LIBCRYPTO_LIB = -lcrypto
DEFAULT_SSL_LIB = -lssl
ifeq ($(uname_S),Linux)
	DEFAULT_LIBUSB_LIB = -lusb-1.0 -lrt
else
	DEFAULT_LIBUSB_LIB = -lusb-1.0
endif
# Since FreeBSD 8 (released in 2010) they are using their own
# libusb that is API compatible to libusb but with different soname
ifeq ($(uname_S),FreeBSD)
	DEFAULT_LIBUSB_LIB = -lusb
endif
ifeq ($(uname_S),Darwin)
	DEFAULT_LIBUSB_FLAGS = -I/opt/local/include
	DEFAULT_LIBUSB_LIB = -L/opt/local/lib -lusb-1.0
	DEFAULT_PCSC_FLAGS = -isysroot $(OSX_SDK)
	DEFAULT_PCSC_LIB = -isysroot $(OSX_SDK) -framework IOKit -framework CoreFoundation -framework PCSC
else
	# Get the compiler's last include PATHs. Basicaly it is /usr/include
	# but in case of cross compilation it might be something else.
	#
	# Since using -Iinc_path instructs the compiler to use inc_path
	# (without add the toolchain system root) we need to have this hack
	# to get the "real" last include path. Why we needs this?
	# Well, the PCSC headers are broken and rely on having the directory
	# that they are installed it to be in the include PATH.
	#
	# We can't just use -I/usr/include/PCSC because it won't work in
	# case of cross compilation.
	TOOLCHAIN_INC_DIR := $(strip $(shell echo | $(CC) -Wp,-v -xc - -fsyntax-only 2>&1 | grep include$ | tail -n 1))
	DEFAULT_PCSC_FLAGS = -I$(TOOLCHAIN_INC_DIR)/PCSC -I$(TOOLCHAIN_INC_DIR)/../local/include/PCSC
	DEFAULT_PCSC_LIB = -lpcsclite
endif

ifeq ($(uname_S),Cygwin)
	#DEFAULT_PCSC_LIB += -lwinscard
	DEFAULT_PCSC_LIB = -lwinscard
endif

DEFAULT_UTF8_FLAGS = -DWITH_UTF8

# Function to initialize USE related variables
#   Usage: $(eval $(call prepare_use_flags,FLAG_NAME,PLUS_TARGET_TEXT))
define prepare_use_flags
override DEFAULT_$(1)_FLAGS:=$$(strip -DWITH_$(1)=1 $$(DEFAULT_$(1)_FLAGS))
ifdef USE_$(1)
	$(1)_FLAGS:=$$(DEFAULT_$(1)_FLAGS)
	$(1)_CFLAGS:=$$($(1)_FLAGS)
	$(1)_LDFLAGS:=$$($(1)_FLAGS)
	$(1)_LIB:=$$(DEFAULT_$(1)_LIB)
	ifneq "$(2)" ""
		override PLUS_TARGET:=$$(PLUS_TARGET)-$(2)
	endif
	override USE_CFLAGS+=$$($(1)_CFLAGS)
	override USE_LDFLAGS+=$$($(1)_LDFLAGS)
	override USE_LIBS+=$$($(1)_LIB)
	override USE_FLAGS+=$$(if $$(USE_$(1)),USE_$(1))
	endif
endef

# Initialize USE variables
$(eval $(call prepare_use_flags,STAPI,stapi))
$(eval $(call prepare_use_flags,STAPI5,stapi5))
$(eval $(call prepare_use_flags,COOLAPI,coolapi))
$(eval $(call prepare_use_flags,COOLAPI2,coolapi2))
$(eval $(call prepare_use_flags,SU980,su980))
$(eval $(call prepare_use_flags,AZBOX,azbox))
$(eval $(call prepare_use_flags,MCA,mca))
$(eval $(call prepare_use_flags,SSL,ssl))
$(eval $(call prepare_use_flags,LIBCRYPTO,))
$(eval $(call prepare_use_flags,LIBUSB,libusb))
$(eval $(call prepare_use_flags,PCSC,pcsc))
$(eval $(call prepare_use_flags,UTF8))

# Add PLUS_TARGET and EXTRA_TARGET to TARGET
ifdef NO_PLUS_TARGET
	override TARGET := $(TARGET)$(EXTRA_TARGET)
else
	override TARGET := $(TARGET)$(PLUS_TARGET)$(EXTRA_TARGET)
endif

EXTRA_CFLAGS = $(EXTRA_FLAGS)
EXTRA_LDFLAGS = $(EXTRA_FLAGS)

# Add USE_xxx, EXTRA_xxx and STD_xxx vars
override CC_WARN += $(EXTRA_CC_WARN)
override CC_OPTS += $(EXTRA_CC_OPTS)
override CFLAGS  += $(USE_CFLAGS) $(EXTRA_CFLAGS)
override LDFLAGS += $(USE_LDFLAGS) $(EXTRA_LDFLAGS)
override LIBS    += $(USE_LIBS) $(EXTRA_LIBS) $(STD_LIBS)

override STD_DEFS += -D'CS_TARGET="$(TARGET)"'

# Setup quiet build
Q =
SAY = @true
ifndef V
	Q = @
	NP = --no-print-directory
	SAY = @echo
endif

BINDIR := Distribution
override BUILD_DIR := build
OBJDIR := $(BUILD_DIR)/$(TARGET)

# Include config.mak which contains variables for all enabled modules
# These variables will be used to select only needed files for compilation
-include $(OBJDIR)/config.mak

NCAM_BIN := $(BINDIR)/ncam-$(VER)$(SVN_REV)-$(subst cygwin,cygwin.exe,$(TARGET))
TESTS_BIN := tests.bin
LIST_SMARGO_BIN := $(BINDIR)/list_smargo-$(VER)$(SVN_REV)-$(subst cygwin,cygwin.exe,$(TARGET))

# Build list_smargo-.... only when WITH_LIBUSB build is requested.
ifndef USE_LIBUSB
	override LIST_SMARGO_BIN =
endif

SRC-$(CONFIG_LIB_AES) += cscrypt/aes.c
SRC-$(CONFIG_LIB_BIGNUM) += cscrypt/bn_add.c
SRC-$(CONFIG_LIB_BIGNUM) += cscrypt/bn_asm.c
SRC-$(CONFIG_LIB_BIGNUM) += cscrypt/bn_ctx.c
SRC-$(CONFIG_LIB_BIGNUM) += cscrypt/bn_div.c
SRC-$(CONFIG_LIB_BIGNUM) += cscrypt/bn_exp.c
SRC-$(CONFIG_LIB_BIGNUM) += cscrypt/bn_lib.c
SRC-$(CONFIG_LIB_BIGNUM) += cscrypt/bn_mul.c
SRC-$(CONFIG_LIB_BIGNUM) += cscrypt/bn_print.c
SRC-$(CONFIG_LIB_BIGNUM) += cscrypt/bn_shift.c
SRC-$(CONFIG_LIB_BIGNUM) += cscrypt/bn_sqr.c
SRC-$(CONFIG_LIB_BIGNUM) += cscrypt/bn_word.c
SRC-$(CONFIG_LIB_BIGNUM) += cscrypt/mem.c
SRC-$(CONFIG_LIB_DES) += cscrypt/des.c
SRC-$(CONFIG_LIB_TWOFISH) += cscrypt/jet_twofish.c
SRC-$(CONFIG_READER_JET) += cscrypt/jet_dh.c
SRC-$(CONFIG_LIB_IDEA) += cscrypt/i_cbc.c
SRC-$(CONFIG_LIB_IDEA) += cscrypt/i_ecb.c
SRC-$(CONFIG_LIB_IDEA) += cscrypt/i_skey.c
SRC-y += cscrypt/md5.c
SRC-$(CONFIG_LIB_RC6) += cscrypt/rc6.c
SRC-$(CONFIG_LIB_SHA1) += cscrypt/sha1.c
SRC-$(CONFIG_LIB_MDC2) += cscrypt/mdc2.c
SRC-$(CONFIG_LIB_FAST_AES) += cscrypt/fast_aes.c
SRC-$(CONFIG_LIB_SHA256) += cscrypt/sha256.c

SRC-$(CONFIG_WITH_CARDREADER) += csctapi/atr.c
SRC-$(CONFIG_WITH_CARDREADER) += csctapi/icc_async.c
SRC-$(CONFIG_WITH_CARDREADER) += csctapi/io_serial.c
SRC-$(CONFIG_WITH_CARDREADER) += csctapi/protocol_t0.c
SRC-$(CONFIG_WITH_CARDREADER) += csctapi/protocol_t1.c
SRC-$(CONFIG_CARDREADER_INTERNAL_AZBOX) += csctapi/ifd_azbox.c
SRC-$(CONFIG_CARDREADER_INTERNAL_COOLAPI) += csctapi/ifd_cool.c
SRC-$(CONFIG_CARDREADER_INTERNAL_COOLAPI2) += csctapi/ifd_cool.c
SRC-$(CONFIG_CARDREADER_DB2COM) += csctapi/ifd_db2com.c
SRC-$(CONFIG_CARDREADER_MP35) += csctapi/ifd_mp35.c
SRC-$(CONFIG_CARDREADER_PCSC) += csctapi/ifd_pcsc.c
SRC-$(CONFIG_CARDREADER_PHOENIX) += csctapi/ifd_phoenix.c
SRC-$(CONFIG_CARDREADER_DRECAS) += csctapi/ifd_drecas.c
SRC-$(CONFIG_CARDREADER_SC8IN1) += csctapi/ifd_sc8in1.c
SRC-$(CONFIG_CARDREADER_INTERNAL_SCI) += csctapi/ifd_sci.c
SRC-$(CONFIG_CARDREADER_SMARGO) += csctapi/ifd_smargo.c
SRC-$(CONFIG_CARDREADER_SMART) += csctapi/ifd_smartreader.c
SRC-$(CONFIG_CARDREADER_STINGER) += csctapi/ifd_stinger.c
SRC-$(CONFIG_CARDREADER_STAPI) += csctapi/ifd_stapi.c
SRC-$(CONFIG_CARDREADER_STAPI5) += csctapi/ifd_stapi.c

SRC-$(CONFIG_LIB_MINILZO) += minilzo/minilzo.c

SRC-$(CONFIG_CS_ANTICASC) += module-anticasc.c
SRC-$(CONFIG_CS_CACHEEX) += module-cacheex.c
SRC-$(CONFIG_MODULE_CAMD33) += module-camd33.c
SRC-$(CONFIG_CS_CACHEEX) += module-camd35-cacheex.c
SRC-$(sort $(CONFIG_MODULE_CAMD35) $(CONFIG_MODULE_CAMD35_TCP)) += module-camd35.c
SRC-$(CONFIG_CS_CACHEEX) += module-cccam-cacheex.c
SRC-$(CONFIG_MODULE_CCCAM) += module-cccam.c
SRC-$(CONFIG_MODULE_CCCSHARE) += module-cccshare.c
SRC-$(CONFIG_MODULE_CONSTCW) += module-constcw.c
SRC-$(CONFIG_WITH_EMU) += module-emulator.c
SRC-$(CONFIG_WITH_EMU) += module-emulator-nemu.c
SRC-$(CONFIG_WITH_EMU) += module-emulator-streamserver.c
SRC-$(CONFIG_WITH_EMU) += module-emulator-biss.c
SRC-$(CONFIG_WITH_EMU) += module-emulator-cryptoworks.c
SRC-$(CONFIG_WITH_EMU) += module-emulator-director.c
SRC-$(CONFIG_WITH_EMU) += module-emulator-drecrypt.c
SRC-$(CONFIG_WITH_EMU) += module-emulator-irdeto.c
SRC-$(CONFIG_WITH_EMU) += module-emulator-nagravision.c
SRC-$(CONFIG_WITH_EMU) += module-emulator-powervu.c
SRC-$(CONFIG_WITH_EMU) += module-emulator-viaccess.c
SRC-$(CONFIG_WITH_EMU) += module-emulator-videoguard.c
SRC-$(CONFIG_WITH_EMU) += ffdecsa/ffdecsa.c

ifeq "$(CONFIG_WITH_EMU)" "y"
ifeq "$(CONFIG_WITH_SOFTCAM)" "y"
UNAME := $(shell uname -s)
ifneq ($(UNAME),Darwin)
ifndef ANDROID_NDK
ifndef ANDROID_STANDALONE_TOOLCHAIN

TOUCH_SK := $(shell touch SoftCam.Key)
override LDFLAGS += -Wl,--format=binary -Wl,SoftCam.Key -Wl,--format=default
endif
endif
endif
endif
endif
SRC-$(CONFIG_CS_CACHEEX) += module-csp.c
SRC-$(CONFIG_CW_CYCLE_CHECK) += module-cw-cycle-check.c
SRC-$(CONFIG_WITH_AZBOX) += module-dvbapi-azbox.c
SRC-$(CONFIG_WITH_MCA) += module-dvbapi-mca.c
### SRC-$(CONFIG_WITH_COOLAPI) += module-dvbapi-coolapi.c
### experimental reversed API
SRC-$(CONFIG_WITH_COOLAPI) += module-dvbapi-coolapi-legacy.c
SRC-$(CONFIG_WITH_COOLAPI2) += module-dvbapi-coolapi.c
SRC-$(CONFIG_WITH_SU980) += module-dvbapi-coolapi.c
SRC-$(CONFIG_WITH_STAPI) += module-dvbapi-stapi.c
SRC-$(CONFIG_WITH_STAPI5) += module-dvbapi-stapi5.c
SRC-$(CONFIG_HAVE_DVBAPI) += module-dvbapi-chancache.c
SRC-$(CONFIG_HAVE_DVBAPI) += module-dvbapi.c
SRC-$(CONFIG_MODULE_GBOX) += module-gbox-helper.c
SRC-$(CONFIG_MODULE_GBOX) += module-gbox-sms.c
SRC-$(CONFIG_MODULE_GBOX) += module-gbox-remm.c
SRC-$(CONFIG_MODULE_GBOX) += module-gbox-cards.c
SRC-$(CONFIG_MODULE_GBOX) += module-gbox.c
SRC-$(CONFIG_IRDETO_GUESSING) += module-ird-guess.c
SRC-$(CONFIG_LCDSUPPORT) += module-lcd.c
SRC-$(CONFIG_LEDSUPPORT) += module-led.c
SRC-$(CONFIG_MODULE_MONITOR) += module-monitor.c
SRC-$(CONFIG_MODULE_NEWCAMD) += module-newcamd.c
SRC-$(CONFIG_MODULE_NEWCAMD) += module-newcamd-des.c
SRC-$(CONFIG_MODULE_PANDORA) += module-pandora.c
SRC-$(CONFIG_MODULE_GHTTP) += module-ghttp.c
SRC-$(CONFIG_MODULE_RADEGAST) += module-radegast.c
SRC-$(CONFIG_MODULE_SCAM) += module-scam.c
SRC-$(CONFIG_MODULE_SERIAL) += module-serial.c
SRC-$(CONFIG_WITH_LB) += module-stat.c
SRC-$(CONFIG_WEBIF) += module-webif-lib.c
SRC-$(CONFIG_WEBIF) += module-webif-tpl.c
SRC-$(CONFIG_WEBIF) += module-webif.c
SRC-$(CONFIG_WEBIF) += webif/pages.c
SRC-$(CONFIG_WITH_CARDREADER) += reader-common.c
SRC-$(CONFIG_READER_BULCRYPT) += reader-bulcrypt.c
SRC-$(CONFIG_READER_CONAX) += reader-conax.c
SRC-$(CONFIG_READER_CRYPTOWORKS) += reader-cryptoworks.c
SRC-$(CONFIG_READER_DGCRYPT) += reader-dgcrypt.c
SRC-$(CONFIG_READER_DRE) += reader-dre.c
SRC-$(CONFIG_READER_DRE) += reader-dre-cas.c
SRC-$(CONFIG_READER_DRE) += reader-dre-common.c
SRC-$(CONFIG_READER_DRE) += reader-dre-st20.c
SRC-$(CONFIG_READER_GRIFFIN) += reader-griffin.c
SRC-$(CONFIG_READER_IRDETO) += reader-irdeto.c
SRC-$(CONFIG_READER_NAGRA_COMMON) += reader-nagra-common.c
SRC-$(CONFIG_READER_NAGRA) += reader-nagra.c
SRC-$(CONFIG_READER_NAGRA_MERLIN) += reader-nagracak7.c
SRC-$(CONFIG_READER_SECA) += reader-seca.c
SRC-$(CONFIG_READER_TONGFANG) += reader-tongfang.c
SRC-$(CONFIG_READER_STREAMGUARD) += reader-streamguard.c
SRC-$(CONFIG_READER_JET) += reader-jet.c
SRC-$(CONFIG_READER_VIACCESS) += reader-viaccess.c
SRC-$(CONFIG_READER_VIDEOGUARD) += reader-videoguard-common.c
SRC-$(CONFIG_READER_VIDEOGUARD) += reader-videoguard1.c
SRC-$(CONFIG_READER_VIDEOGUARD) += reader-videoguard12.c
SRC-$(CONFIG_READER_VIDEOGUARD) += reader-videoguard2.c
SRC-y += ncam-aes.c
SRC-y += ncam-array.c
SRC-y += ncam-hashtable.c
SRC-y += ncam-cache.c
SRC-y += ncam-chk.c
SRC-y += ncam-client.c
SRC-y += ncam-conf.c
SRC-y += ncam-conf-chk.c
SRC-y += ncam-conf-mk.c
SRC-y += ncam-config-account.c
SRC-y += ncam-config-global.c
SRC-y += ncam-config-reader.c
SRC-y += ncam-config.c
SRC-y += ncam-ecm.c
SRC-y += ncam-emm.c
SRC-y += ncam-emm-cache.c
SRC-y += ncam-failban.c
SRC-y += ncam-files.c
SRC-y += ncam-garbage.c
SRC-y += ncam-lock.c
SRC-y += ncam-log.c
SRC-y += ncam-log-reader.c
SRC-y += ncam-net.c
SRC-y += ncam-llist.c
SRC-y += ncam-reader.c
SRC-y += ncam-simples.c
SRC-y += ncam-string.c
SRC-y += ncam-time.c
SRC-y += ncam-work.c
SRC-y += ncam.c
# config.c is automatically generated by config.sh in OBJDIR
SRC-y += config.c
ifdef BUILD_TESTS
	SRC-y += tests.c
	override STD_DEFS += -DBUILD_TESTS=1
endif

SRC := $(SRC-y)
OBJ := $(addprefix $(OBJDIR)/,$(subst .c,.o,$(SRC)))
SRC := $(subst config.c,$(OBJDIR)/config.c,$(SRC))

# The default build target rebuilds the config.mak if needed and then
# starts the compilation.
all:
	@./config.sh --use-flags "$(USE_FLAGS)" --objdir "$(OBJDIR)" --make-config.mak
	@-mkdir -p $(OBJDIR)/cscrypt $(OBJDIR)/csctapi $(OBJDIR)/minilzo $(OBJDIR)/ffdecsa $(OBJDIR)/webif
	@-printf "\
+-------------------------------------------------------------------------------\n\
| NCam ver: $(VER) rev: $(SVN_REV) target: $(TARGET)\n\
| Tools:\n\
|  CROSS    = $(CROSS_DIR)$(CROSS)\n\
|  CC       = $(CC)\n\
| Settings:\n\
|  CONF_DIR = $(CONF_DIR)\n\
|  CC_OPTS  = $(strip $(CC_OPTS))\n\
|  CC_WARN  = $(strip $(CC_WARN))\n\
|  CFLAGS   = $(strip $(CFLAGS))\n\
|  LDFLAGS  = $(strip $(LDFLAGS))\n\
|  LIBS     = $(strip $(LIBS))\n\
|  UseFlags = $(addsuffix =1,$(USE_FLAGS))\n\
| Config:\n\
|  Addons   : $(shell ./config.sh --use-flags "$(USE_FLAGS)" --show-enabled addons)\n\
|  Protocols: $(shell ./config.sh --use-flags "$(USE_FLAGS)" --show-enabled protocols | sed -e 's|MODULE_||g')\n\
|  Readers  : $(shell ./config.sh --use-flags "$(USE_FLAGS)" --show-enabled readers | sed -e 's|READER_||g')\n\
|  CardRdrs : $(shell ./config.sh --use-flags "$(USE_FLAGS)" --show-enabled card_readers | sed -e 's|CARDREADER_||g')\n\
|  Compiler : $(shell $(CC) --version 2>/dev/null | head -n 1)\n\
|  Config   : $(OBJDIR)/config.mak\n\
|  Binary   : $(NCAM_BIN)\n\
+-------------------------------------------------------------------------------\n"
ifeq "$(shell ./config.sh --enabled WEBIF)" "Y"
	@$(MAKE) --no-print-directory --quiet -C webif
endif
	@$(MAKE) --no-print-directory $(NCAM_BIN) $(LIST_SMARGO_BIN)

$(NCAM_BIN).debug: $(OBJ)
	$(SAY) "LINK	$@"
	$(Q)$(CC) $(LDFLAGS) $(OBJ) $(LIBS) -o $@

$(NCAM_BIN): $(NCAM_BIN).debug
	$(SAY) "STRIP	$@"
	$(Q)cp $(NCAM_BIN).debug $(NCAM_BIN)
	$(Q)$(STRIP) $(NCAM_BIN)

$(LIST_SMARGO_BIN): utils/list_smargo.c
	$(SAY) "BUILD	$@"
	$(Q)$(CC) $(STD_DEFS) $(CC_OPTS) $(CC_WARN) $(CFLAGS) $(LDFLAGS) utils/list_smargo.c $(LIBS) -o $@

$(OBJDIR)/config.o: $(OBJDIR)/config.c
	$(SAY) "CONF	$<"
	$(Q)$(CC) $(STD_DEFS) $(CC_OPTS) $(CC_WARN) $(CFLAGS) -c $< -o $@

$(OBJDIR)/%.o: %.c Makefile
	@$(CC) -MP -MM -MT $@ -o $(subst .o,.d,$@) $<
	$(SAY) "CC	$<"
	$(Q)$(CC) $(STD_DEFS) $(CC_OPTS) $(CC_WARN) $(CFLAGS) -c $< -o $@

-include $(subst .o,.d,$(OBJ))

tests:
	@-$(MAKE) --no-print-directory BUILD_TESTS=1 NCAM_BIN=$(TESTS_BIN)
	@-touch ncam.c
# The above is really hideous hack :-) If we don't force ncam.c recompilation
# after we've build the tests binary, the next "normal" compilation would fail
# because there would be no run_tests() function. So the touch is there to
# ensure ncam.c would be recompiled.

config:
	$(SHELL) ./config.sh --gui

menuconfig: config

allyesconfig:
	@echo "Enabling all config options."
	@-$(SHELL) ./config.sh --enable all

allnoconfig:
	@echo "Disabling all config options."
	@-$(SHELL) ./config.sh --disable all

defconfig:
	@echo "Restoring default config."
	@-$(SHELL) ./config.sh --restore

clean:
	@-for FILE in $(BUILD_DIR)/* $(TESTS_BIN) $(TESTS_BIN).debug; do \
		echo "RM	$$FILE"; \
		rm -rf $$FILE; \
	done
	@-rm -rf $(BUILD_DIR) lib

distclean: clean
	@-for FILE in $(BINDIR)/list_smargo-* $(BINDIR)/ncam-$(VER)*; do \
		echo "RM	$$FILE"; \
		rm -rf $$FILE; \
	done
	@-$(MAKE) --no-print-directory --quiet -C webif clean

README.build:
	@echo "Extracting 'make help' into $@ file."
	@-printf "\
** This file is generated from 'make help' output, do not edit it. **\n\
\n\
" > $@
	@-$(MAKE) --no-print-directory help >> $@
	@echo "Done."

README.config:
	@echo "Extracting 'config.sh --help' into $@ file."
	@-printf "\
** This file is generated from 'config.sh --help' output, do not edit it. **\n\
\n\
" > $@
	@-./config.sh --help >> $@
	@echo "Done."

help:
	@-printf "\
NCam build system documentation\n\
================================\n\
\n\
 Build variables:\n\
   The build variables are set on the make command line and control the build\n\
   process. Setting the variables lets you enable additional features, request\n\
   extra libraries and more. Currently recognized build variables are:\n\
\n\
   CROSS=prefix   - Set tools prefix. This variable is used when NCam is being\n\
                    cross compiled. For example if you want to cross compile\n\
                    for SH4 architecture you can run: 'make CROSS=sh4-linux-'\n\
                    If you don't have the directory where cross compilers are\n\
                    in your PATH you can run:\n\
                    'make CROSS=/opt/STM/STLinux-2.3/devkit/sh4/bin/sh4-linux-'\n\
\n\
   CROSS_DIR=dir  - Set tools directory. This variable is added in front of\n\
                    CROSS variable. CROSS_DIR is useful if you want to use\n\
                    predefined targets that are setting CROSS, but you don't have\n\
                    the cross compilers in your PATH. For example:\n\
                    'make sh4 CROSS_DIR=/opt/STM/STLinux-2.3/devkit/sh4/bin/'\n\
                    'make dm500 CROSS_DIR=/opt/cross/dm500/cdk/bin/'\n\
\n\
   CONF_DIR=/dir  - Set NCam config directory. For example to change config\n\
                    directory to /etc run: 'make CONF_DIR=/etc'\n\
                    The default config directory is: '$(CONF_DIR)'\n\
\n\
   CC_OPTS=text   - This variable holds compiler optimization parameters.\n\
                    Default CC_OPTS value is:\n\
                    '$(CC_OPTS)'\n\
                    To add text to this variable set EXTRA_CC_OPTS=text.\n\
\n\
   CC_WARN=text   - This variable holds compiler warning parameters.\n\
                    Default CC_WARN value is:\n\
                    '$(CC_WARN)'\n\
                    To add text to this variable set EXTRA_CC_WARN=text.\n\
\n\
   V=1            - Request build process to print verbose messages. By\n\
                    default the only messages that are shown are simple info\n\
                    what is being compiled. To request verbose build run:\n\
                    'make V=1'\n\
\n\
 Extra build variables:\n\
   These variables add text to build variables. They are useful if you want\n\
   to add additional options to already set variables without overwriting them\n\
   Currently defined EXTRA_xxx variables are:\n\
\n\
   EXTRA_CC_OPTS  - Add text to CC_OPTS.\n\
                    Example: 'make EXTRA_CC_OPTS=-Os'\n\
\n\
   EXTRA_CC_WARN  - Add text to CC_WARN.\n\
                    Example: 'make EXTRA_CC_WARN=-Wshadow'\n\
\n\
   EXTRA_TARGET   - Add text to TARGET.\n\
                    Example: 'make EXTRA_TARGET=-private'\n\
\n\
   EXTRA_CFLAGS   - Add text to CFLAGS (affects compilation).\n\
                    Example: 'make EXTRA_CFLAGS=\"-DBLAH=1 -I/opt/local\"'\n\
\n\
   EXTRA_LDFLAGS  - Add text to LDFLAGS (affects linking).\n\
                    Example: 'make EXTRA_LDFLAGS=-Llibdir'\n\
\n\
   EXTRA_FLAGS    - Add text to both EXTRA_CFLAGS and EXTRA_LDFLAGS.\n\
                    Example: 'make EXTRA_FLAGS=-DBLAH=1'\n\
\n\
   EXTRA_LIBS     - Add text to LIBS (affects linking).\n\
                    Example: 'make EXTRA_LIBS=\"-L./stapi -lncam_stapi\"'\n\
\n\
 Use flags:\n\
   Use flags are used to request additional libraries or features to be used\n\
   by NCam. Currently defined USE_xxx flags are:\n\
\n\
   USE_LIBUSB=1    - Request linking with libusb. The variables that control\n\
                     USE_LIBUSB=1 build are:\n\
                         LIBUSB_FLAGS='$(DEFAULT_LIBUSB_FLAGS)'\n\
                         LIBUSB_CFLAGS='$(DEFAULT_LIBUSB_FLAGS)'\n\
                         LIBUSB_LDFLAGS='$(DEFAULT_LIBUSB_FLAGS)'\n\
                         LIBUSB_LIB='$(DEFAULT_LIBUSB_LIB)'\n\
                     Using USE_LIBUSB=1 adds to '-libusb' to PLUS_TARGET.\n\
                     To build with static libusb, set the variable LIBUSB_LIB\n\
                     to contain full path of libusb library. For example:\n\
                      make USE_LIBUSB=1 LIBUSB_LIB=/usr/lib/libusb-1.0.a\n\
\n\
   USE_PCSC=1      - Request linking with PCSC. The variables that control\n\
                     USE_PCSC=1 build are:\n\
                         PCSC_FLAGS='$(DEFAULT_PCSC_FLAGS)'\n\
                         PCSC_CFLAGS='$(DEFAULT_PCSC_FLAGS)'\n\
                         PCSC_LDFLAGS='$(DEFAULT_PCSC_FLAGS)'\n\
                         PCSC_LIB='$(DEFAULT_PCSC_LIB)'\n\
                     Using USE_PCSC=1 adds to '-pcsc' to PLUS_TARGET.\n\
                     To build with static PCSC, set the variable PCSC_LIB\n\
                     to contain full path of PCSC library. For example:\n\
                      make USE_PCSC=1 PCSC_LIB=/usr/local/lib/libpcsclite.a\n\
\n\
   USE_STAPI=1    - Request linking with STAPI. The variables that control\n\
                     USE_STAPI=1 build are:\n\
                         STAPI_FLAGS='$(DEFAULT_STAPI_FLAGS)'\n\
                         STAPI_CFLAGS='$(DEFAULT_STAPI_FLAGS)'\n\
                         STAPI_LDFLAGS='$(DEFAULT_STAPI_FLAGS)'\n\
                         STAPI_LIB='$(DEFAULT_STAPI_LIB)'\n\
                     Using USE_STAPI=1 adds to '-stapi' to PLUS_TARGET.\n\
                     In order for USE_STAPI to work you have to create stapi\n\
                     directory and put libncam_stapi.a file in it.\n\
\n\
   USE_STAPI5=1    - Request linking with STAPI5. The variables that control\n\
                     USE_STAPI5=1 build are:\n\
                         STAPI5_FLAGS='$(DEFAULT_STAPI5_FLAGS)'\n\
                         STAPI5_CFLAGS='$(DEFAULT_STAPI5_FLAGS)'\n\
                         STAPI5_LDFLAGS='$(DEFAULT_STAPI5_FLAGS)'\n\
                         STAPI5_LIB='$(DEFAULT_STAPI5_LIB)'\n\
                     Using USE_STAPI5=1 adds to '-stapi' to PLUS_TARGET.\n\
                     In order for USE_STAPI5 to work you have to create stapi\n\
                     directory and put libncam_stapi5.a file in it.\n\
\n\
   USE_COOLAPI=1  - Request support for Coolstream API (libnxp) aka NeutrinoHD\n\
                    box. The variables that control the build are:\n\
                         COOLAPI_FLAGS='$(DEFAULT_COOLAPI_FLAGS)'\n\
                         COOLAPI_CFLAGS='$(DEFAULT_COOLAPI_FLAGS)'\n\
                         COOLAPI_LDFLAGS='$(DEFAULT_COOLAPI_FLAGS)'\n\
                         COOLAPI_LIB='$(DEFAULT_COOLAPI_LIB)'\n\
                     Using USE_COOLAPI=1 adds to '-coolapi' to PLUS_TARGET.\n\
                     In order for USE_COOLAPI to work you have to have libnxp.so\n\
                     library in your cross compilation toolchain.\n\
\n\
   USE_COOLAPI2=1  - Request support for Coolstream API aka NeutrinoHD\n\
                    box. The variables that control the build are:\n\
                         COOLAPI_FLAGS='$(DEFAULT_COOLAPI2_FLAGS)'\n\
                         COOLAPI_CFLAGS='$(DEFAULT_COOLAPI2_FLAGS)'\n\
                         COOLAPI_LDFLAGS='$(DEFAULT_COOLAPI2_FLAGS)'\n\
                         COOLAPI_LIB='$(DEFAULT_COOLAPI2_LIB)'\n\
                     Using USE_COOLAPI2=1 adds to '-coolapi2' to PLUS_TARGET.\n\
                     In order for USE_COOLAPI2 to work you have to have liblnxUKAL.so,\n\
                     liblnxcssUsr.so, liblnxscsUsr.so, liblnxnotifyqUsr.so, liblnxplatUsr.so\n\
                     library in your cross compilation toolchain.\n\
\n\
   USE_SU980=1  - Request support for SU980 API (libentropic) aka Enimga2 arm\n\
                    box. The variables that control the build are:\n\
                         COOLAPI_FLAGS='$(DEFAULT_SU980_FLAGS)'\n\
                         COOLAPI_CFLAGS='$(DEFAULT_SU980_FLAGS)'\n\
                         COOLAPI_LDFLAGS='$(DEFAULT_SU980_FLAGS)'\n\
                         COOLAPI_LIB='$(DEFAULT_SU980_LIB)'\n\
                     Using USE_SU980=1 adds to '-su980' to PLUS_TARGET.\n\
                     In order for USE_SU980 to work you have to have libentropic.a\n\
                     library in your cross compilation toolchain.\n\
\n\
   USE_AZBOX=1    - Request support for AZBOX (openxcas)\n\
                    box. The variables that control the build are:\n\
                         AZBOX_FLAGS='$(DEFAULT_AZBOX_FLAGS)'\n\
                         AZBOX_CFLAGS='$(DEFAULT_AZBOX_FLAGS)'\n\
                         AZBOX_LDFLAGS='$(DEFAULT_AZBOX_FLAGS)'\n\
                         AZBOX_LIB='$(DEFAULT_AZBOX_LIB)'\n\
                     Using USE_AZBOX=1 adds to '-azbox' to PLUS_TARGET.\n\
                     extapi/openxcas/libOpenXCASAPI.a library that is shipped\n\
                     with NCam is compiled for MIPSEL.\n\
\n\
   USE_MCA=1      - Request support for Matrix Cam Air (MCA).\n\
                    The variables that control the build are:\n\
                         MCA_FLAGS='$(DEFAULT_MCA_FLAGS)'\n\
                         MCA_CFLAGS='$(DEFAULT_MCA_FLAGS)'\n\
                         MCA_LDFLAGS='$(DEFAULT_MCA_FLAGS)'\n\
                     Using USE_MCA=1 adds to '-mca' to PLUS_TARGET.\n\
\n\
   USE_LIBCRYPTO=1 - Request linking with libcrypto instead of using NCam\n\
                     internal crypto functions. USE_LIBCRYPTO is automatically\n\
                     enabled if the build is configured with SSL support. The\n\
                     variables that control USE_LIBCRYPTO=1 build are:\n\
                         LIBCRYPTO_FLAGS='$(DEFAULT_LIBCRYPTO_FLAGS)'\n\
                         LIBCRYPTO_CFLAGS='$(DEFAULT_LIBCRYPTO_FLAGS)'\n\
                         LIBCRYPTO_LDFLAGS='$(DEFAULT_LIBCRYPTO_FLAGS)'\n\
                         LIBCRYPTO_LIB='$(DEFAULT_LIBCRYPTO_LIB)'\n\
\n\
   USE_SSL=1       - Request linking with libssl. USE_SSL is automatically\n\
                     enabled if the build is configured with SSL support. The\n\
                     variables that control USE_SSL=1 build are:\n\
                         SSL_FLAGS='$(DEFAULT_SSL_FLAGS)'\n\
                         SSL_CFLAGS='$(DEFAULT_SSL_FLAGS)'\n\
                         SSL_LDFLAGS='$(DEFAULT_SSL_FLAGS)'\n\
                         SSL_LIB='$(DEFAULT_SSL_LIB)'\n\
                     Using USE_SSL=1 adds to '-ssl' to PLUS_TARGET.\n\
\n\
   USE_UTF8=1       - Request UTF-8 enabled webif by default.\n\
\n\
 Automatically intialized variables:\n\
\n\
   TARGET=text     - This variable is auto detected by using the compiler's\n\
                    -dumpmachine output. To see the target on your machine run:\n\
                     'gcc -dumpmachine'\n\
\n\
   PLUS_TARGET     - This variable is added to TARGET and it is set depending\n\
                     on the chosen USE_xxx flags. To disable adding\n\
                     PLUS_TARGET to TARGET, set NO_PLUS_TARGET=1\n\
\n\
   BINDIR          - The directory where final ncam binary would be put. The\n\
                     default is: $(BINDIR)\n\
\n\
   NCAM_BIN=text  - This variable controls how the ncam binary will be named.\n\
                     Default NCAM_BIN value is:\n\
                      'BINDIR/ncam-VERSVN_REV-TARGET'\n\
                     Once the variables (BINDIR, VER, SVN_REV and TARGET) are\n\
                     replaced, the resulting filename can look like this:\n\
                      'Distribution/ncam-1.20-unstable_svn7404-i486-slackware-linux-static'\n\
                     For example you can run: 'make NCAM_BIN=my-ncam'\n\
\n\
 Binaries compiled and run during the NCam build:\n\
\n\
   NCam builds webif/pages_gen binary that is run by the build system to\n\
   generate file that holds web pages. To build this binary two variables\n\
   are used:\n\
\n\
   HOSTCC=gcc     - The compiler used for building binaries that are run on\n\
                    the build machine (the host). Default: gcc\n\
                    To use clang for example run: make CC=clang HOSTCC=clang\n\
\n\
   HOSTCFLAGS=xxx - The CFLAGS passed to HOSTCC. See webif/Makefile for the\n\
                    default host cflags.\n\
\n\
 Config targets:\n\
   make config        - Start configuration utility.\n\
   make allyesconfig  - Enable all configuration options.\n\
   make allnoconfig   - Disable all configuration options.\n\
   make defconfig     - Restore default configuration options.\n\
\n\
 Cleaning targets:\n\
   make clean     - Remove '$(BUILD_DIR)' directory which contains compiled\n\
                    object files.\n\
   make distclean - Executes clean target and also removes binary files\n\
                    located in '$(BINDIR)' directory.\n\
\n\
 Build system files:\n\
   config.sh      - NCam configuration. Run 'config.sh --help' to see\n\
                    available parameters or 'make config' to start GUI\n\
                    configuratior.\n\
   Makefile       - Main build system file.\n\
   Makefile.extra - Contains predefined targets. You can use this file\n\
                    as example on how to use the build system.\n\
   Makefile.local - This file is included in Makefile and allows creation\n\
                    of local build system targets. See Makefile.extra for\n\
                    examples.\n\
\n\
 Here are some of the interesting predefined targets in Makefile.extra.\n\
 To use them run 'make target ...' where ... can be any extra flag. For\n\
 example if you want to compile NCam for Dreambox (DM500) but do not\n\
 have the compilers in the path, you can run:\n\
    make dm500 CROSS_DIR=/opt/cross/dm500/cdk/bin/\n\
\n\
 Predefined targets in Makefile.extra:\n\
\n\
    make libusb        - Builds NCam with libusb support\n\
    make pcsc          - Builds NCam with PCSC support\n\
    make pcsc-libusb   - Builds NCam with PCSC and libusb support\n\
    make dm500         - Builds NCam for Dreambox (DM500)\n\
    make sh4           - Builds NCam for SH4 boxes\n\
    make azbox         - Builds NCam for AZBox STBs\n\
    make mca           - Builds NCam for Matrix Cam Air (MCA)\n\
    make coolstream    - Builds NCam for Coolstream HD1\n\
    make coolstream2   - Builds NCam for Coolstream HD2\n\
    make dockstar      - Builds NCam for Dockstar\n\
    make qboxhd        - Builds NCam for QBoxHD STBs\n\
    make opensolaris   - Builds NCam for OpenSolaris\n\
    make uclinux       - Builds NCam for m68k uClinux\n\
\n\
 Predefined targets for static builds:\n\
    make static        - Builds NCam statically\n\
    make static-libusb - Builds NCam with libusb linked statically\n\
    make static-libcrypto - Builds NCam with libcrypto linked statically\n\
    make static-ssl    - Builds NCam with SSL support linked statically\n\
\n\
 Developer targets:\n\
    make tests         - Builds '$(TESTS_BIN)' binary\n\
\n\
 Examples:\n\
   Build NCam for SH4 (the compilers are in the path):\n\
     make CROSS=sh4-linux-\n\n\
   Build NCam for SH4 (the compilers are in not in the path):\n\
     make sh4 CROSS_DIR=/opt/STM/STLinux-2.3/devkit/sh4/bin/\n\
     make CROSS_DIR=/opt/STM/STLinux-2.3/devkit/sh4/bin/ CROSS=sh4-linux-\n\
     make CROSS=/opt/STM/STLinux-2.3/devkit/sh4/bin/sh4-linux-\n\n\
   Build NCam for SH4 with STAPI:\n\
     make CROSS=sh4-linux- USE_STAPI=1\n\n\
   Build NCam for SH4 with STAPI and changed configuration directory:\n\
     make CROSS=sh4-linux- USE_STAPI=1 CONF_DIR=/var/tuxbox/config\n\n\
   Build NCam for ARM with COOLAPI (coolstream aka NeutrinoHD):\n\
     make CROSS=arm-cx2450x-linux-gnueabi- USE_COOLAPI=1\n\n\
   Build NCam for ARM with COOLAPI2 (coolstream aka NeutrinoHD):\n\
     make CROSS=arm-pnx8400-linux-uclibcgnueabi- USE_COOLAPI2=1\n\n\
   Build NCam for MIPSEL with AZBOX support:\n\
     make CROSS=mipsel-linux-uclibc- USE_AZBOX=1\n\n\
   Build NCam for ARM with MCA support:\n\
     make CROSS=arm-none-linux-gnueabi- USE_MCA=1\n\n\
   Build NCAm for Android with STAPI and changed configuration directory:\n\
     make CROSS=arm-linux-androideabi- USE_WI=1 CONF_DIR=/data/plugin/ncam\n\n\
   Build NCam with libusb and PCSC:\n\
     make USE_LIBUSB=1 USE_PCSC=1\n\n\
   Build NCam with static libusb:\n\
     make USE_LIBUSB=1 LIBUSB_LIB=\"/usr/lib/libusb-1.0.a\"\n\n\
   Build NCam with static libcrypto:\n\
     make USE_LIBCRYPTO=1 LIBCRYPTO_LIB=\"/usr/lib/libcrypto.a\"\n\n\
   Build NCam with static libssl and libcrypto:\n\
     make USE_SSL=1 SSL_LIB=\"/usr/lib/libssl.a\" LIBCRYPTO_LIB=\"/usr/lib/libcrypto.a\"\n\n\
   Build with verbose messages and size optimizations:\n\
     make V=1 CC_OPTS=-Os\n\n\
   Build and set ncam file name:\n\
     make NCAM_BIN=ncam\n\n\
   Build and set ncam file name depending on revision:\n\
     make NCAM_BIN=ncam-\`./config.sh -r\`\n\n\
"

simple: all
default: all
debug: all

-include Makefile.extra
-include Makefile.local
