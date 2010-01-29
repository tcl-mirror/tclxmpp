# pkgIndex.tcl --
#
#       This file is part of the XMPP library. It registeres XMPP packages
#       for Tcl.
#
# Copyright (c) 2008-2010 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package ifneeded pconnect 0.1                   [list source [file join $dir pconnect.tcl]]
package ifneeded pconnect::https 0.1            [list source [file join $dir https.tcl]]
package ifneeded pconnect::socks4 0.1           [list source [file join $dir socks4.tcl]]
package ifneeded pconnect::socks5 0.1           [list source [file join $dir socks5.tcl]]
package ifneeded xmpp 0.1                       [list source [file join $dir xmpp.tcl]]
package ifneeded xmpp::auth 0.1                 [list source [file join $dir auth.tcl]]
package ifneeded xmpp::bob 0.1                  [list source [file join $dir bob.tcl]]
package ifneeded xmpp::component 0.1            [list source [file join $dir component.tcl]]
package ifneeded xmpp::compress 0.1             [list source [file join $dir compress.tcl]]
package ifneeded xmpp::data 0.1                 [list source [file join $dir data.tcl]]
package ifneeded xmpp::delay 0.1                [list source [file join $dir delay.tcl]]
package ifneeded xmpp::disco 0.1                [list source [file join $dir disco.tcl]]
package ifneeded xmpp::dns 0.1                  [list source [file join $dir dns.tcl]]
package ifneeded xmpp::iq 0.1                   [list source [file join $dir iq.tcl]]
package ifneeded xmpp::jid 0.1                  [list source [file join $dir jid.tcl]]
package ifneeded xmpp::muc 0.1                  [list source [file join $dir muc.tcl]]
package ifneeded xmpp::negotiate 0.1            [list source [file join $dir negotiate.tcl]]
package ifneeded xmpp::pep 0.1                  [list source [file join $dir pep.tcl]]
package ifneeded xmpp::ping 0.1                 [list source [file join $dir ping.tcl]]
package ifneeded xmpp::presence 0.1             [list source [file join $dir presence.tcl]]
package ifneeded xmpp::privacy 0.1              [list source [file join $dir privacy.tcl]]
package ifneeded xmpp::private 0.1              [list source [file join $dir private.tcl]]
package ifneeded xmpp::pubsub 0.1               [list source [file join $dir pubsub.tcl]]
package ifneeded xmpp::register 0.1             [list source [file join $dir register.tcl]]
package ifneeded xmpp::roster 0.1               [list source [file join $dir roster.tcl]]
package ifneeded xmpp::roster::annotations 0.1  [list source [file join $dir annotations.tcl]]
package ifneeded xmpp::roster::bookmarks 0.1    [list source [file join $dir bookmarks.tcl]]
package ifneeded xmpp::roster::delimiter 0.1    [list source [file join $dir delimiter.tcl]]
package ifneeded xmpp::roster::metacontacts 0.1 [list source [file join $dir metacontacts.tcl]]
package ifneeded xmpp::sasl 0.1                 [list source [file join $dir sasl.tcl]]
package ifneeded xmpp::search 0.1               [list source [file join $dir search.tcl]]
package ifneeded xmpp::stanzaerror 0.1          [list source [file join $dir stanzaerror.tcl]]
package ifneeded xmpp::starttls 0.1             [list source [file join $dir starttls.tcl]]
package ifneeded xmpp::streamerror 0.1          [list source [file join $dir streamerror.tcl]]
package ifneeded xmpp::transport 0.1            [list source [file join $dir transport.tcl]]
package ifneeded xmpp::transport::poll 0.1      [list source [file join $dir poll.tcl]]
package ifneeded xmpp::transport::tcp 0.1       [list source [file join $dir tcp.tcl]]
package ifneeded xmpp::transport::tls 0.1       [list source [file join $dir tls.tcl]]
package ifneeded xmpp::transport::zlib 0.1      [list source [file join $dir zlib.tcl]]
package ifneeded xmpp::xml 0.1                  [list source [file join $dir xml.tcl]]

package ifneeded xmpp::full 0.1 {
    package require pconnect::https 0.1
    package require pconnect::socks4 0.1
    package require pconnect::socks5 0.1
    package require xmpp 0.1
    package require xmpp::auth 0.1
    package require xmpp::bob 0.1
    package require xmpp::component 0.1
    package require xmpp::compress 0.1
    package require xmpp::delay 0.1
    package require xmpp::disco 0.1
    package require xmpp::dns 0.1
    package require xmpp::muc 0.1
    package require xmpp::pep 0.1
    package require xmpp::ping 0.1
    package require xmpp::privacy 0.1
    package require xmpp::roster 0.1
    package require xmpp::roster::annotations 0.1
    package require xmpp::roster::bookmarks 0.1
    package require xmpp::roster::delimiter 0.1
    package require xmpp::roster::metacontacts 0.1
    package require xmpp::starttls 0.1
    package require xmpp::transport::poll 0.1
    package require xmpp::transport::tls 0.1
    package require xmpp::transport::zlib 0.1

    package provide xmpp::full 0.1
}

# vim:ts=8:sw=4:sts=4:et
