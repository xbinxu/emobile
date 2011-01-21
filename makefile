ROOT_DIR  = $(shell pwd)
OUT_DIR   = $(ROOT_DIR)/ebin


%.o: override ERL_ROOT  ?= $(shell erl -noshell -eval 'io:format("~s~n", [code:root_dir()]).' -s init stop)
%.o: override ERTS_ROOT ?= $(ERL_ROOT)/usr

%.o: override INCLUDES += -I$(ERTS_ROOT)/include
%.o: override LIBS     += -L$(ERTS_ROOT)/lib -lerts

%.o: override EI_ROOT  ?= $(shell erl -noshell -eval 'io:format("~s~n", [code:lib_dir(erl_interface)]).' -s init stop)

%.o: override INCLUDES += -I$(EI_ROOT)/include
%.o: override LIBS     += -L$(EI_ROOT)/lib -lei -lerl_interface -lrt

ifeq ($(shell uname), Darwin)
  %.o: override OPTIONS   += -fno-common -bundle -undefined suppress -flat_namespace
  %.o: override USR_LOCAL = /opt/local
else
  %.o: override USR_LOCAL = /usr/local
endif

%.o: override INCLUDES += -I$(USR_LOCAL)/include
%.o: override LIBS     += -L$(USR_LOCAL)/lib

export %.o:INCLUDES %.o:LIBS

EINCLUDES  ?= $(shell for loop in `find . -name "*.hrl" -type f -print | xargs echo | sed "s/\.\///g" | sed "s/\/\w*\.hrl//g"`; \
                      do \
                          NEWINCLUDE=-I\""`pwd`"/$$loop\"; \
                          if [ ! "$$NEWINCLUDE" = "$$OLDINCLUDE" ]; then \
                              echo "$$NEWINCLUDE"; \
                          fi ; \
                          OLDINCLUDE=$$NEWINCLUDE; \
                      done)
                     
HRL_FILES ?= $(shell for loop in `find . -name "*.hrl" -type f -print | xargs echo | sed "s/\.\///g"`;\
                     do  \
                         echo "`pwd`/$$loop "; \
                     done)

export ROOT_DIR OUT_DIR EINCLUDES HRL_FILESS

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
	for dir in $(SUBDIRS); do \
		cd $$dir && make && cd ..; \
	done 

# remove all the code
clean:
	rm -rf $(OUT_DIR)/*.beam $(OUT_DIR)/erl_crash.dump
