CC ?= cc
PKG_CONFIG ?= pkg-config
include compatibility.conf

ifeq ($(strip $(CYSHELL_LABWC_SUPPORTED_VERSION)),)
$(error compatibility.conf must declare CYSHELL_LABWC_SUPPORTED_VERSION)
endif
ifeq ($(strip $(CYSHELL_WLROOTS_ABI_MAJOR)),)
$(error compatibility.conf must declare CYSHELL_WLROOTS_ABI_MAJOR)
endif
ifeq ($(strip $(CYSHELL_WLROOTS_ABI_MINOR)),)
$(error compatibility.conf must declare CYSHELL_WLROOTS_ABI_MINOR)
endif

WLROOTS_PACKAGE = wlroots-$(CYSHELL_WLROOTS_ABI_MAJOR).$(CYSHELL_WLROOTS_ABI_MINOR)
CFLAGS ?= -O2 -g
CPPFLAGS += -DWLR_USE_UNSTABLE $(shell $(PKG_CONFIG) --cflags $(WLROOTS_PACKAGE) wayland-server)
CPPFLAGS += -DCYSHELL_LABWC_SUPPORTED_VERSION='"$(CYSHELL_LABWC_SUPPORTED_VERSION)"'
CPPFLAGS += -DCYSHELL_WLROOTS_ABI_MAJOR=$(CYSHELL_WLROOTS_ABI_MAJOR)
CPPFLAGS += -DCYSHELL_WLROOTS_ABI_MINOR=$(CYSHELL_WLROOTS_ABI_MINOR)
CFLAGS += -fPIC -Wall -Wextra -Wpedantic
LDLIBS += -ldl $(shell $(PKG_CONFIG) --libs $(WLROOTS_PACKAGE) wayland-server)

TARGET = libcyshell-labwc-bridge.so
SRC = bridge.c

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SRC) compatibility.conf Makefile
	$(CC) $(CPPFLAGS) $(CFLAGS) -shared -Wl,-z,relro,-z,now -o $@ $< $(LDLIBS)

clean:
	rm -f $(TARGET)
