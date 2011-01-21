ROOT_DIR  = $(shell pwd)
OUT_DIR   = $(ROOT_DIR)/ebin


ERL_ROOT  ?= $(shell erl -noshell -eval 'io:format("~s~n", [code:root_dir()]).' -s init stop)
ERTS_ROOT ?= $(ERL_ROOT)/usr

INCLUDES += -I$(ERTS_ROOT)/include
LIBS     += -L$(ERTS_ROOT)/lib -lerts

EI_ROOT  ?= $(shell erl -noshell -eval 'io:format("~s~n", [code:lib_dir(erl_interface)]).' -s init stop)

INCLUDES += -I$(EI_ROOT)/include
LIBS     += -L$(EI_ROOT)/lib -lei -lerl_interface -lrt

ifeq ($(shell uname), Darwin)
  OPTIONS   += -fno-common -bundle -undefined suppress -flat_namespace
  USR_LOCAL = /opt/local
else
  USR_LOCAL = /usr/local
endif

INCLUDES += -I$(USR_LOCAL)/include
LIBS     += -L$(USR_LOCAL)/lib

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

export ROOT_DIR OUT_DIR INCLUDES LIBS EINCLUDES HRL_FILESS ERL_ROOT ERTS_ROOT EI_ROOT

include makefile.inc

# The first target in any makefile is the default target.
# If you just type "make" then "make all" is assumed (because
# "all" is the first target in this makefile)
all: compile
compile: subdirs

# the subdirs target compiles any code in
# sub-directories
subdirs:
	cd src && make
	cd mysql && make


# remove all the code
clean:
	rm -rf $(OUT_DIR)/*.beam $(OUT_DIR)/erl_crash.dump
	cd src && make clean
	cd mysql && make clean
