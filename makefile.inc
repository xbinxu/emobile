# leave these lines alone

.SUFFIXES: .erl .beam .yrl .c .cpp .o

OUT_DIR   = $(ROOT_DIR)/ebin

ERL_ROOT  = $(shell erl -noshell -eval 'io:format("~s~n", [code:root_dir()]).' -s init stop)

ERTS_ROOT = $(shell erl -noshell -eval 'io:format("~s~n", [code:root_dir()]).' -s init stop)/usr
INCLUDES += -I$(ERTS_ROOT)/include
LIBS     += -L$(ERTS_ROOT)/lib -lerts

EI_ROOT  = $(shell erl -noshell -eval 'io:format("~s~n", [code:lib_dir(erl_interface)]).' -s init stop)
INCLUDES += -I$(EI_ROOT)/include
LIBS     += -L$(EI_ROOT)/lib -lei -lerl_interface -lrt

CFLAGS = -DDYNAMIC_DRIVER -fpic -g -O2
OPTIONS = -fpic -O2

ifeq ($(shell uname), Darwin)
  OPTIONS   += -fno-common -bundle -undefined suppress -flat_namespace
  USR_LOCAL = /opt/local
else
  USR_LOCAL = /usr/local
endif

INCLUDES += -I$(USR_LOCAL)/include
LIBS     += -L$(USR_LOCAL)/lib


#EFLAGS = +export_all +debug_info +native +"{hipe, [o3]}"
EFLAGS = +export_all +debug_info 

EINCLUDES  = -I$(ROOT_DIR)/include

ERL = erl -boot start_clean

.erl.beam:
	erlc $(EFLAGS) $(EINCLUDES) -o $(ROOT_DIR)/ebin -W $<

.yrl.erl:
	erlc -W $<
	
.cpp.o:
	g++ $(CFLAGS) $(INCLUDES) -c $<
	
.c.o:
	gcc $(CFLAGS) $(INCLUDES) -c $<




