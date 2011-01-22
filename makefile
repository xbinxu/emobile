include makefile.env
include makefile.inc

# The first target in any makefile is the default target.
# If you just type "make" then "make all" is assumed (because
# "all" is the first target in this makefile)
all: compile
compile: subdirs

subdirs:override SUBDIRS = $(filter-out $(IGNORE_DIRS), $(shell ls -F | grep /$ | sed "s/\///g"))

# the subdirs target compiles any code in
# sub-directories
subdirs: 
	@for dir in $(SUBDIRS); do \
		cd $$dir && make && cd ..; \
	done 

.PHONY: clean

# remove all the code
clean:
	-rm -rf $(OUT_DIR)/*.beam $(OUT_DIR)/erl_crash.dump
