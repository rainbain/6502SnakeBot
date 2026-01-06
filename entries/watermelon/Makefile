SRC = main.asm
BIN = watermelon.bin

CA65 = ca65
LD65 = ld65

LINKER_CFG = raw.cfg

all: $(BIN)

main.o: $(SRC)
	$(CA65) $(SRC) -o main.o

$(BIN): main.o $(LINKER_CFG)
	$(LD65) main.o -C $(LINKER_CFG) -o $(BIN)

clean:
	rm -f *.o $(BIN)

.PHONY: all clean
