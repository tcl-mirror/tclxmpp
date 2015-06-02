# TclXMPP Makefile

# Tcl can't find libraries in /usr/local hierarchy, so install
# the libraries into /usr/lib
LIBDIR = /usr/lib

# The binaries and docs go to /usr/local by default
PREFIX = /usr/local
BINDIR = $(PREFIX)/bin
DOCDIR = $(PREFIX)/share/doc/tclxmpp
MANDIR = $(PREFIX)/share/man

SUBDIRS = xmpp \
	  tclxml

MANPAGES3 = doc/xmpp.3 \
	    doc/xmpp_jid.3 \
	    doc/xmpp_xml.3

MANPAGES1 = examples/jsend.1 \
	    examples/rssbot.1

all: doc

doc: $(MANPAGES3) $(MANPAGES1)

%.3: %.man
	mpexpand nroff $< $@

%.1: %.man
	mpexpand nroff $< $@

install: install-lib install-bin install-doc install-examples

install-lib:
	install -d $(DESTDIR)$(LIBDIR)
	cp -dr --no-preserve=ownership $(SUBDIRS) $(DESTDIR)$(LIBDIR)

install-bin:
	install -d $(DESTDIR)$(BINDIR)
	install -m 755 -T examples/jsend.tcl $(DESTDIR)$(BINDIR)/jsend
	install -m 755 -T examples/rssbot.tcl $(DESTDIR)$(BINDIR)/rssbot

install-doc: doc
	install -d $(DESTDIR)$(DOCDIR)
	install -d $(DESTDIR)$(MANDIR)/man1
	install -d $(DESTDIR)$(MANDIR)/man3
	install -m 644 ChangeLog license.terms $(DESTDIR)$(DOCDIR)
	install -m 644 $(MANPAGES1) $(DESTDIR)$(MANDIR)/man1
	install -m 644 $(MANPAGES3) $(DESTDIR)$(MANDIR)/man3

install-examples:
	install -d $(DESTDIR)$(DOCDIR)/examples
	install -m 755 examples/*.tcl $(DESTDIR)$(DOCDIR)/examples

# Update TclXMPP from Fossil repository
up:
	test -f .fslckout -o -f _FOSSIL_ && fossil update

.PHONY: all doc install install-lib install-bin install-doc install-examples up
