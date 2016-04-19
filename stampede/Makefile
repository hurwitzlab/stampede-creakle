clean:
	find . \( -name \*.conf -o -name \*.out -o -name \*.log -o -name \*.params -o -name launcher-\* \) -exec rm {} \;

dna1:
	./00-controller.sh -s $(WORK)/mouse/fasta/DNA1 -q $(WORK)/mouse/fasta/DNA1 -o $(WORK)/creakle-out/DNA1 -m 2 -p normal -t "24:00:00"

count:
	./00-controller.sh -r 01-count.sh -s $(WORK)/mouse/fasta/DNA1 -q $(WORK)/mouse/fasta/DNA1 -o $(WORK)/creakle-out -m 1 -p development -t "02:00:00"

compare:
	./00-controller.sh -r 02-compare.sh -s $(WORK)/mouse/fasta/DNA1 -q $(WORK)/mouse/fasta/DNA1 -o $(WORK)/creakle-out -m 1 -p development -t "02:00:00"

screen:
	./00-controller.sh -r 03-screen.sh -s $(WORK)/mouse/fasta/DNA1 -q $(WORK)/mouse/fasta/DNA1 -o $(WORK)/creakle-out -m 1 -p development -t "02:00:00"
