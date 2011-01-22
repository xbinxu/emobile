include $(ROOT_DIR)/makefile.inc


# The first target in any makefile is the default target.
# If you just type "make" then "make all" is assumed (because
# "all" is the first target in this makefile)
all: compile cfg subdirs

MODS = $(wildcard *.erl)
APPS = $(wildcard *.app)
compile: ${MODS:%.erl=$(OUT_DIR)/%.beam}
cfg: ${APPS:%.app=$(OUT_DIR)/%.app}

.PHONY: subdirs clean

subdirs:override SUBDIRS = $(filter-out $(IGNORE_DIRS), $(shell ls -F | grep /$ | sed "s/\///g"))

# the subdirs target compiles any code in
# sub-directories
subdirs: 
	@for dir in $(SUBDIRS); do \
		cd $$dir && make && cd ..; \
	done 
	
clean:
	rm -rf *.beam erl_crash.dump