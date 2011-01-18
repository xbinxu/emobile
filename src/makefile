include ../makefile.inc


# The first target in any makefile is the default target.
# If you just type "make" then "make all" is assumed (because
# "all" is the first target in this makefile)
all: compile subdirs

MODS = $(wildcard *.erl)
compile: ${MODS:%.erl=%.beam}

subdirs:
	cd common && ROOT_DIR=$(ROOT_DIR) make
	cd ctl_node && ROOT_DIR=$(ROOT_DIR) make
	cd push_node && ROOT_DIR=$(ROOT_DIR) make
	cd conn_node && ROOT_DIR=$(ROOT_DIR) make	

clean:
	rm -rf *.beam erl_crash.dump
	cd common && ROOT_DIR=$(ROOT_DIR) make clean
	cd ctl_node && ROOT_DIR=$(ROOT_DIR) make clean
	cd push_node && ROOT_DIR=$(ROOT_DIR) make clean
	cd conn_node && ROOT_DIR=$(ROOT_DIR) make clean