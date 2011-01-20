ROOT_DIR = $(shell pwd)

include makefile.inc

# The first target in any makefile is the default target.
# If you just type "make" then "make all" is assumed (because
# "all" is the first target in this makefile)
all: compile
compile: subdirs

# the subdirs target compiles any code in
# sub-directories
subdirs:
	cd src && ROOT_DIR=$(ROOT_DIR) make
	cd mysql && ROOT_DIR=$(ROOT_DIR) make


# remove all the code
clean:
	rm -rf $(ROOT_DIR)/ebin/*.beam ebin/erl_crash.dump
	cd src; ROOT_DIR=$(ROOT_DIR) make clean

