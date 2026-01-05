EMULATOR := ./emulator/emulator
ENTRIES := ./entries
ENTRY ?= golden

.phony: all
all: $(EMULATOR)

$(EMULATOR):
	make -C ./emulator

.phony: test
test: $(EMULATOR)
	make -C $(ENTRIES)/$(ENTRY)
	$(EMULATOR) --rom $(ENTRIES)/$(ENTRY)/$(ENTRY).bin

.phony: debug
debug: $(EMULATOR)
	make -C $(ENTRIES)/$(ENTRY) clean
	make -C $(ENTRIES)/$(ENTRY)
	$(EMULATOR) --rom $(ENTRIES)/$(ENTRY)/$(ENTRY).bin	

.phony: clean
clean:
	find $(ENTRIES) -type f -name "*.bin" -delete
	find $(ENTRIES) -type f -name "*.o" -delete
	make -C ./emulator clean
