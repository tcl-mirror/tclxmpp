#!/usr/bin/env tclsh

# rssbot.tcl --
#
#       This file is an example provided with the XMPP library. It implements
#       RSS/XMPP gateway. It was initially developed by Marshall T. Rose and
#       adapted to the XMPP library by Sergei Golovan.
#
# Copyright (c) 2009 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require Tcl 8.5
package require http 2
package require mime
package require tls
package require uri

package require xmpp
package require xmpp::auth
package require xmpp::sasl
package require xmpp::starttls
package require xmpp::roster
package require xmpp::private
package require xmpp::delay

# Register IQ XMLNS
::xmpp::iq::register get * http://jabber.org/protocol/disco#info \
                           xsend::iqDiscoInfo
::xmpp::iq::register get * http://jabber.org/protocol/disco#items \
                           xsend::iqDiscoItems
::xmpp::iq::register get * jabber:iq:last    xsend::iqLast
::xmpp::iq::register get * jabber:iq:time    xsend::iqTime
::xmpp::iq::register get * jabber:iq:version xsend::iqVersion

namespace eval rssbot {}

proc rssbot::sendit {stayP to args} {
    global env
    global xlib

    variable lib
    variable roster

    array set options [list -to          $to      \
                            -from        ""       \
                            -password    ""       \
                            -host        ""       \
                            -port        ""       \
                            -activity    ""       \
                            -type        headline \
                            -subject     ""       \
                            -date        ""       \
                            -body        ""       \
                            -description ""       \
                            -url         ""       \
                            -tls         false    \
                            -starttls    true     \
                            -sasl        true]
    array set options $args

    if {![string compare $options(-host) ""]} {
        set options(-host) [info hostname]
    }

    set params [list from]
    foreach k $params {
        if {[string first @ $options(-$k)] < 0} {
            if {[set x [string first / $options(-$k)]] >= 0} {
                set options(-$k) [string replace $options(-$k) $x $x \
                                         @$options(-host)/]
            } else {
                append options(-$k) @$options(-host)
            }
        }
        if {([string first @ $options(-$k)] == 0) \
                && ([info exists env(USER)])} {
            set options(-$k) $env(USER)$options(-$k)
        }
    }

    foreach k [list tls starttls] {
        switch -- [string tolower $options(-$k)] {
            1 - 0               {}
            false - no  - off   { set options(-$k) 0 }
            true  - yes - on    { set options(-$k) 1 }
            default {
                error "invalid value for -$k: $options(-$k)"
            }
        }
    }

    array set aprops [lindex [mime::parseaddress $options(-from)] 0]
    if {[set x [string first / $aprops(domain)]] >= 0} {
        set aprops(resource) [string range $aprops(domain) [expr {$x + 1}] end]
        set aprops(domain) [string range $aprops(domain) 0 [expr {$x - 1}]]
    } else {
        set aprops(resource) "rssbot"
    }

    set options(-xlist) {}
    if {[string compare $options(-url)$options(-description) ""]} {
        lappend options(-xlist) \
                [::xmpp::xml::create x \
                        -xmlns jabber:x:oob \
                        -subelement [::xmpp::xml::create url \
                                        -cdata $options(-url)] \
                        -subelement [::xmpp::xml::create desc \
                                        -cdata $options(-description)]]
    }
    if {[string compare $options(-date) ""]} {
        lappend options(-xlist) \
                [::xmpp::delay::create $options(-date)]
    }

    set lib(lastwhat) $options(-activity)
    if {[catch { clock scan $options(-time) } lib(lastwhen)]} {
        set lib(lastwhen) [clock seconds]
    }

    set params {}
    foreach k [list body subject type xlist] {
        if {[string compare $options(-$k) ""]} {
            lappend params -$k $options(-$k)
        }
    }

    if {![info exists xlib]} {
        # Create an XMPP library instance
        set xlib [::xmpp::new -messagecommand [namespace current]::message \
                              -presencecommand [namespace current]::presence]

        if {$options(-tls)} {
            set transport tls
            if {![string equal $options(-port) ""]} {
                set port $options(-port)
            } else {
                set port 5223
            }
        } else {
            set transport tcp
            if {![string equal $options(-port) ""]} {
                set port $options(-port)
            } else {
                set port 5222
            }
        }

        # Connect to a server
        ::xmpp::connect $xlib $aprops(domain) $port -transport $transport

        if {!$options(-tls) && $options(-starttls)} {
            # Open XMPP stream
            set sessionID [::xmpp::openStream $xlib $aprops(domain) \
                                                    -version 1.0]

            ::xmpp::starttls::starttls $xlib

            ::xmpp::sasl::auth $xlib -username  $aprops(local) \
                                     -password  $options(-password) \
                                     -resource  $aprops(resource)
        } elseif {$options(-sasl)} {
            # Open XMPP stream
            set sessionID [::xmpp::openStream $xlib $aprops(domain) \
                                                    -version 1.0]

            ::xmpp::sasl::auth $xlib -username  $aprops(local) \
                                     -password  $options(-password) \
                                     -resource  $aprops(resource)
        } else {
            # Open XMPP stream
            set sessionID [::xmpp::openStream $xlib $aprops(domain)]

            # Authenticate
            ::xmpp::auth::auth $xlib -sessionid $sessionID \
                                     -username  $aprops(local) \
                                     -password  $options(-password) \
                                     -resource  $aprops(resource)
        }

        set roster [::xmpp::roster::new $xlib]
        ::xmpp::roster::get $roster
    }

    if {$stayP > 1} {
        ::xmpp::sendPresence $xlib -status Online

        return 1
    }

    foreach to $options(-to) {
        switch -- [eval [list ::xmpp::sendMessage $xlib $to] $params] {
            -1 -
            -2 {
                if {$stayP} {
                    set cmd [list ::LOG]
                } else {
                    set cmd [list error]
                }
                eval $cmd [list "error writing to socket, continuing..."]
                return 0
            }
            default {}
        }
    }
    if {!$stayP} {
        ::xmpp::disconnect $xlib
    }

    return 1
}

proc rssbot::message {xlib from type x args} {
    ::LOG "rssbot::message $from $type $x $args"

    set jid [::xmpp::jid::stripResource $from]

    switch -- $type {
        normal -
        chat { }
        "" { set type normal }
        default {
            ::LOG "$from ignoring $type"
            return
        }
    }

    set body ""
    set subject ""
    foreach {key val} $args {
        switch -- $key {
            -body { set body $val }
            -subject { set subject $val }
        }
    }

    if {[catch { rssbot::message_aux $jid $body } answer]} {
        ::LOG "$jid/$body: $answer"
        set answer "internal error, sorry! ($answer)"
    }
    if {[catch { rssbot::sendit 1 "" \
                     -to       $from         \
                     -activity "$jid: $body" \
                     -type     $type         \
                     -subject  $subject      \
                     -body     $answer } result]} {
        ::LOG "$from: $result"
    }
}

proc rssbot::presence {xlib from type x args} {
    variable articles
    variable sources
    variable subscribers

    ::LOG "rssbot:presence $from $type $x $args"

    set jid [::xmpp::jid::stripResource $from]

    switch -- $type {
        available -
        unavailable { }
        "" { set type available }
        default {
            ::LOG "$from ignoring $type"
            return
        }
    }

    rssbot::presence_aux $jid $type
}

proc rssbot::iqDiscoInfo {xlib from xmlElement args} {
    ::LOG "rssbot::iqDiscoInfo $from"

    ::xmpp::xml::split $xmlElement tag xmlns attrs cdata subels

    if {[::xmpp::xml::isAttr $attrs node]} {
        return [list error cancel service-unavailable]
    }

    set identity [::xmpp::xml::create identity \
                                      -attrs [list name     rssbot \
                                                   category client \
                                                   type     bot]]

    set subelements {}
    foreach var [list http://jabber.org/protocol/disco#info \
                      http://jabber.org/protocol/disco#items \
                      jabber:iq:last \
                      jabber:iq:time \
                      jabber:iq:version] {
        lappend subelements [::xmpp::xml::create feature \
                                    -attrs [list var $var]]
    }
    set xmldata \
        [::xmpp::xml::create query -xmlns       $xmlns \
                                   -attrs       [list type client] \
                                   -subelement  $identity \
                                   -subelements $subelements]
    return [list result $xmldata]
}

proc rssbot::iqDiscoItems {xlib from xmlElement args} {
    ::LOG "rssbot::iqDiscoItems $from"

    ::xmpp::xml::split $xmlElement tag xmlns attrs cdata subels

    if {[::xmpp::xml::isAttr $attrs node]} {
        return [list error cancel service-unavailable]
    }

    return [list result [::xmpp::xml::create query -xmlns $xmlns]]
}

proc rssbot::iqLast {xlib from xmlElement args} {
    variable lib

    ::LOG "rssbot::iqLast $from"

    set now [clock seconds]
    set xmldata \
        [::xmpp::xml::create query -xmlns jabber:iq:last \
                                   -attrs [list seconds \
                                                [expr {$now - $lib(lastwhen)}]] \
                                   -cdata $lib(lastwhat)]
    return [list result $xmldata]
}

proc rssbot::iqTime {xlib from xmlElement args} {
    ::LOG "rssbot::iqTime $from"

    set now [clock seconds]
    set gmtP true
    foreach {k f} [list utc     "%Y%m%dT%T" \
                        tz      "%Z"        \
                        display "%a %b %d %H:%M:%S %Z %Y"] {
        lappend tags [::xmpp::xml::create $k -cdata [clock format $now \
                                                           -format $f  \
                                                           -gmt    $gmtP]]
        set gmtP false
    }
    set xmldata [::xmpp::xml::create query -xmlns jabber:iq:time \
                                           -subelements $tags]
    return [list result $xmldata]
}

proc rssbot::iqVersion {xlib from xmlElement args} {
    global argv0 tcl_platform

    ::LOG "rssbot::iqVersion $from"

    foreach {k v} [list name    [file tail [file rootname $argv0]] \
                        version "1.0 (Tcl [info patchlevel])"      \
                        os      "$tcl_platform(os) $tcl_platform(osVersion)"] {
        lappend tags [::xmpp::xml::create $k -cdata $v]
    }
    set xmldata [::xmpp::xml::create query -xmlns jabber:iq:version \
                                           -subelements $tags]
    return [list result $xmldata]
}

proc client:reconnect {xlib} {
    rssbot::reconnect
}

proc client:disconnect {xlib} {
    rssbot::reconnect
}

proc client:status {args} {
    ::LOG "client:status $args"
}

# state variables
#     mtime - modified time
#     ntime - expiration time
#
#
# articles(source,url)    [list mtime ... ntime ... args { ... }  source "..."]
# sources(site)           [list mtime ... ntime ...]
# subscribers(jid)        [list mtime ...           sites { ... } status "..."]
#

proc rssbot::begin {argv} {
    global xlib
    global doneP

    variable iqP
    variable loopID
    variable parser

    variable articles
    variable sources
    variable subscribers

    proc [namespace current]::reconnect {} \
         [list [namespace current]::reconnect_aux $argv]

    if {[catch {
        set loopID ""
        [set parser [xml::parser]] configure \
                -elementstartcommand  [namespace code [list element begin]] \
                -elementendcommand    [namespace code [list element end]]   \
                -characterdatacommand [namespace code pcdata]

        array set articles {}
        array set sources {}
        array set subscribers {}

        eval [list rssbot::sendit 2 ""] $argv

        set iqP 0
        foreach array [list articles sources subscribers] {
            incr iqP
            ::xmpp::private::retrieve $xlib \
                    [list [::xmpp::xml::create $array \
                                    -xmlns rssbot.$array]] \
                -command [namespace code [list iq_private 0]]
        }
        while {$iqP > 0} {
            vwait [namespace current]::iqP
        }

        loop $argv
    } result]} {
        set doneP 1
        bgerror $result
    }
}

proc rssbot::loop {argv} {
    variable loopID

    set loopID ""

    if {[catch { loop_aux $argv } result]} {
        bgerror $result
    }

    set loopID [after [expr {30*60*1000}] [list [namespace current]::loop $argv]]
}

proc rssbot::loop_aux {argv} {
    global xlib
    variable articles
    variable sources
    variable subscribers
    variable lib

    array set updateP [list articles 0 sources 0 subscribers 0]

    set sites {}
    foreach jid [array names subscribers] {
        array set props $subscribers($jid)

        if {![string compare $props(status) available]} {
            foreach site $props(sites) {
                if {[lsearch -exact $sites $site] < 0} {
                    lappend sites $site
                }
            }
        }
    }

    set now [clock seconds]
    foreach site $sites {
        catch { array unset sprops }
        array set sprops [list ntime 0]
        catch { array set sprops $sources($site) }

        if {$sprops(ntime) > $now} {
            continue
        }

        if {[catch { ::http::geturl $site } httpT]} {
            ::LOG "$site: $httpT"
            continue
        }

        switch -exact -- [set status [::http::status $httpT]] {
            ok {
                if {![string match 2* [set ncode [::http::ncode $httpT]]]} {
                    ::LOG "$site: returns code $ncode"
                } else {
                    catch { unset state }
                    upvar #0 $httpT state

                    catch { unset array meta }
                    array set meta $state(meta)
                    if {![info exists meta(Last-Modified)]} {
                        set mtime $now
                    } elseif {[catch { rfc2822::parseDate $meta(Last-Modified) } t]} {
                        ::LOG "$site: invalid Last-Modified meta-data $meta(Last-Modified)"
                        set mtime $now
                    } else {
                        set mtime $t
                    }
                    foreach {k v} [process $site $mtime [expr {$now + (30*60)}] \
                                           $now [::http::data $httpT]] {
                        if {$v} {
                            set updateP($k) 1
                        }
                    }
                }
            }
            timeout -
            default {
                ::LOG "$site: $status"
            }
        }

        ::http::cleanup $httpT
    }

    foreach jid [array names subscribers] {
        catch { array unset props }
        array set props $subscribers($jid)

        if {[catch { set props(mtime) } mtime]} {
            set mtime 0
        }

        set xtime 0
        foreach site $props(sites) {
            foreach article [array names articles] {
                catch { array unset aprops }
                array set aprops $articles($article)

                if {$aprops(ntime) <= $now} {
                    unset articles($article)

                    set updateP(articles) 1
                    continue
                }

                if {[string first "$site," $article]} {
                    continue
                }

                if {$aprops(mtime) <= $mtime} {
                    continue
                }

                if {[catch { eval [list rssbot::sendit 1 $jid] $argv \
                                  $aprops(args) } result]} {
                    ::LOG "$jid: $result"
                } else {
                    if {$xtime < $aprops(mtime)} {
                        set xtime $aprops(mtime)
                    }

                    set lib(lastwhat) $aprops(source)
                    set lib(lastwhen) $aprops(mtime)
                }
            }
        }

        if {$xtime > $mtime} {
            set updateP(subscribers) 1

            set props(mtime) $xtime
            set subscribers($jid) [array get props]
        }
    }

    foreach array [list articles sources subscribers] {
        if {$updateP($array)} {
            ::xmpp::private::store $xlib \
                    [list [::xmpp::xml::create $array \
                                    -xmlns rssbot.$array \
                                    -cdata [array get $array]]] \
                -command [namespace code [list iq_private 1]]
        }
    }
}

proc rssbot::process {site mtime ntime now data} {
    variable info
    variable parser
    variable stack

    variable sources

    array set info [list site $site ctime $mtime now $now articleP 0]

    set stack {}
    if {[catch { $parser parse $data } result]} {
        ::LOG "$site: $result"
    } else {
        set sources($site) [list mtime $mtime ntime $ntime]
    }

    return [list articles $info(articleP) sources $info(articleP)]
}

proc rssbot::element {tag name {av {}} args} {
    variable info
    variable stack

    variable articles

    switch -- $tag {
        begin {
            set parent [lindex [lindex $stack end] 0]
            lappend stack [list $name $av]
            switch -- $parent/$name {
                channel/title {
                    array set info [list subject ""]
                }
                channel/item -
                rdf:RDF/item -
                RDF/item {
                    array set info [list description "" \
                                         body        "" \
                                         url         "" \
                                         date        ""]
                }
            }
        }
        end {
            set stack [lreplace $stack end end]
            set parent [lindex [lindex $stack end] 0]

            switch -- $parent/$name {
                channel/item -
                rdf:RDF/item -
                RDF/item {}
                default {
                    return
                }
            }

            if {[string compare $info(date) ""]} {
                if {[catch { iso8601::parse_date $info(date) } info(mtime)] && \
                        [catch { iso8601::parse_time $info(date) } info(mtime)] && \
                        [catch { rfc2822::parseDate $info(date) } info(mtime)]} {
                    ::LOG "$info(site): invalid date $info(date)"
                    set info(mtime) $info(ctime)
                }
            } else {
                set info(mtime) $info(ctime)
            }

            if {![string compare [set url $info(url)] ""]} {
                ::LOG "$info(site): missing URL in item"
                return
            }

            set ntime [expr {$info(mtime) + (7*24*60*60)}]
            if {$ntime <= $info(now)} {
                ::LOG "DEBUG $info(site): article for $url at $info(date) is expired"
                return
            }

            set site $info(site)
            if {[info exists articles($site,$url)]} {
                ::LOG "DEBUG $info(site): article for $url already exists"
                return
            }

            if {![string compare $info(body) ""]} {
                set info(body) [string trim "$info(description)\n$info(url)"]
            }

            set args {}
            foreach k [list subject body description url] {
                lappend args -$k [string trim $info($k)]
            }
            lappend args -date $info(mtime)

            set articles($site,$url) \
                [list mtime  $info(mtime)                 \
                      ntime  $ntime                       \
                      source [string trim $info(subject)] \
                      args   $args]

            set info(articleP) 1
        }
    }
}

proc rssbot::pcdata {text} {
    variable info
    variable stack

    if {![string compare [string trim $text] ""]} {
        return
    }

    set name [lindex [lindex $stack end] 0]
    set parent [lindex [lindex $stack end-1] 0]
    switch -- $parent/$name {
        channel/title {
            append info(subject) $text
        }
        item/title {
            append info(description) $text
        }
        item/link {
            append info(url) $text
        }
        item/description {
            append info(body) $text
        }
        item/dc:date -
        item/date -
        item/pubDate {
            append info(date) $text
        }
    }
}

proc rssbot::message_aux {jid request} {
    global xlib
    variable loopID

    variable articles
    variable sources
    variable subscribers
    variable roster

    if {[catch { split [string trim $request] } args]} {
        return $args
    }

    set answer ""
    set updateP 0
    set arrayL [list subscribers]

    set fmt "%a %b %d %H:%M:%S %Z %Y"
    switch -glob -- [set arg0 [string tolower [lindex $args 0]]] {
        h* {
            set answer {commands are:
    subscribe URL
    unsubscribe [URL ...]
    reset [DATE-TIME]
    list
    dump [URL ...]
    flush
    help}
        }
        sub* {
            if {[llength $args] <= 1} {
                return "usage: subscribe URL ..."
            }

            array set props [list mtime 0 sites {} status available]
            if {([catch { array set props $subscribers($jid) }]) \
                    && ([lsearch -exact [::xmpp::roster::items $roster] $jid] < 0)} {
                return "not authorized"
            }

            set s ""
            foreach arg [lrange $args 1 end] {
                if {![string compare $arg ""]} {
                    append answer $s "invalid source: empty URL"
                } elseif {[lsearch -exact $props(sites) $arg] >= 0} {
                    append answer $s "already subscribed to $arg"
                } elseif {[catch { uri::split $arg } result]} {
                    append answer $s "invalid source: $arg ($result)"
                } else {
                    lappend props(sites) $arg
                    set updateP 1

                    append answer $s "added subscription to $arg"
                }
                set s "\n"
            }
        }
        unsub* {
            if {![info exists subscribers($jid)]} {
                return "no subscriptions"
            }

            array set props $subscribers($jid)
            if {[llength $args] <= 1} {
                set s {}
                foreach site $props(sites) {
                    lappend s "cancelled subscription to $site"
                }
                append answer [join $s \n]

                set props(sites) {}
                set updateP 1
            } else {
                set s {}
                foreach arg [lrange $args 1 end] {
                    if {[set x [lsearch -exact $props(sites) $arg]] < 0} {
                        lappend s "not subscribed to $arg"
                    } else {
                        set props(sites) [lreplace $props(sites) $x $x]
                        set updateP 1

                        lappend s "cancelled subscription to $arg"
                    }
                }
                append answer [join $s \n]
            }
        }
        reset {
            if {![info exists subscribers($jid)]} {
                return "no subscriptions"
            }

            array set props $subscribers($jid)

            append answer "subscription history reset"
            if {[llength $args] <= 1} {
                set props(mtime) 0
            } elseif {[catch { clock scan [concat [lrange $args 1 end]] \
                                     -base [clock seconds] } m]} {
                return "invalid date-time: [concat [lrange $args 1 end]] ($m)"
            } else {
                set props(mtime) $m
                append answer " to [clock format $m -format $fmt]"
            }
            set updateP 1
        }
        list {
            if {![info exists subscribers($jid)]} {
                return "no subscriptions"
            }

            array set props $subscribers($jid)

            if {[llength $props(sites)] == 0} {
                append answer "no sites"
            } else {
                append answer [join $props(sites) \n]
            }
        }
        dump {
            if {![info exists subscribers($jid)]} {
                return [::xmpp::xml::toTabbedText \
                            [::xmpp::xml::create subscriber \
                                    -attrs [list jid $jid]]]
            }

            array set props $subscribers($jid)

            set tags {}

            if {[info exists props(mtime)]} {
                set cdata [clock format $props(mtime) -format $fmt]
            } else {
                set cdata never
            }
            lappend tags [::xmpp::xml::create updated -cdata $cdata]

            foreach site $props(sites) {
                if {([llength $args] > 1) && \
                        ([lsearch -exact [lrange $args 1 end] $site] < 0)} {
                    continue
                }

                catch { unset array sprops }
                array set sprops $sources($site)

                set stags {}
                lappend stags [::xmpp::xml::create url -cdata $site]
                lappend stags [::xmpp::xml::create modified \
                                   -cdata [clock format $sprops(mtime) \
                                                 -format $fmt]]
                lappend stags [::xmpp::xml::create expires \
                                   -cdata [clock format $sprops(ntime) \
                                                 -format $fmt]]
                set atags {}
                foreach article [array names articles] {
                    if {[string first "$site," $article]} {
                        continue
                    }
                    set url [string range $article [string length "$site,"] end]

                    catch { array unset aprops }
                    array set aprops $articles($article)

                    set atag {}
                    lappend atag [::xmpp::xml::create url -cdata $url]
                    lappend atag [::xmpp::xml::create modified \
                                      -cdata [clock format $aprops(mtime) \
                                                    -format $fmt]]
                    lappend atag [::xmpp::xml::create expires \
                                      -cdata [clock format $aprops(ntime) \
                                                    -format $fmt]]
                    lappend atag [::xmpp::xml::create args \
                                      -cdata $aprops(args)]

                    lappend atags [::xmpp::xml::create article \
                                       -subelements $atag]
                }

                lappend stags [::xmpp::xml::create articles \
                                   -subelements $atags]

                lappend tags [::xmpp::xml::create site \
                                  -subelements $stags]
            }

            set answer [::xmpp::xml::toTabbedText \
                            [::xmpp::xml::create subscriber \
                                    -attrs [list jid $jid] \
                                    -subelement [::xmpp::xml::create sites \
                                                        -subelements $tags]]]
        }
        flush {
            if {![info exists subscribers($jid)]} {
                return "no subscriptions"
            }

            array set props $subscribers($jid)

            foreach array [set arrayL [list articles sources]] {
                lappend arrayL $array
                array unset $array
                array set $array {}
            }
            set updateP 1

            append answer "cache flushed"
        }
        default {
            append answer "unknown request: $arg0\n"
            append answer "try \"help\" instead"
        }
    }

    if {$updateP} {
        set subscribers($jid) [array get props]

        foreach array $arrayL {
            ::xmpp::private::store $xlib \
                    [list [::xmpp::xml::create $array \
                                    -xmlns rssbot.$array \
                                    -cdata [array get $array]]] \
                    -command [namespace code [list iq_private 1]]
        }

        if {[string compare $loopID ""]} {
            set script [lindex [after info $loopID] 0]
            after cancel $loopID
            set loopID [after idle $script]
        }
    }

    return $answer
}


proc rssbot::presence_aux {jid status} {
    global xlib
    variable loopID

    variable articles
    variable sources
    variable subscribers

    if {![info exists subscribers($jid)]} {
        ::LOG "$jid not subscribed?!?"
        return
    }

    array set props $subscribers($jid)

    if {[string compare $props(status) $status]} {
        set props(status) $status
        set subscribers($jid) [array get props]

        ::xmpp::private::store $xlib \
                [list [::xmpp::xml::create subscribers \
                                -xmlns rssbot.subscribers \
                                -cdata [array get subscribers]]] \
                -command [namespace code [list iq_private 1]]

        if {(![string compare $status available]) \
                && ([string compare $loopID ""])} {
            set script [lindex [after info $loopID] 0]
            after cancel $loopID
            set loopID [after idle $script]
        }
    }
}


proc rssbot::reconnect_aux {argv} {
    while {1} {
        after [expr {60*1000}]
        if {![catch { eval [list rssbot::sendit 2 ""] $argv } result]} {
            break
        }

        ::LOG $result
    }
}

proc rssbot::iq_private {setP status xmlList} {
    global doneP

    variable iqP

    variable articles
    variable sources
    variable subscribers

    if {[set code [catch {
        if {[string compare $status ok]} {
            error "iq_private: [lindex $xmlList 0]"
        }

        if {$setP} {
            return
        }

        ::xmpp::xml::split [lindex $xmlList 0] tag xmlns attrs cdata subels

        if {[catch { llength $cdata }]} {
            error "iq_private: bad data: $cdata"
        }

        switch -- $xmlns {
            rssbot.articles -
            rssbot.sources -
            rssbot.subscribers {
                array set [string range $xmlns 7 end] $cdata
            }
            default {
                error "iq_private: unexpected namespace: $xmlns"
            }
        }

        incr iqP -1
    } result]]} {
        if {$code == 2} {
            return
        }

        set doneP 1
        set iqP 0
        bgerror $result
    }
}

# The following code is taken from http://wiki.tcl.tk/13094

namespace eval iso8601 {

    namespace export parse_date parse_time

    # Enumerate the patterns that we recognize for an ISO8601 date as both
    # the regexp patterns that match them and the [clock] patterns that scan
    # them.

    variable DatePatterns {
        {\d\d\d\d-\d\d-\d\d}            {%Y-%m-%d}
        {\d\d\d\d\d\d\d\d}              {%Y%m%d}
        {\d\d\d\d-\d\d\d}               {%Y-%j}
        {\d\d\d\d\d\d\d}                {%Y%j}
        {\d\d-\d\d-\d\d}                {%y-%m-%d}
        {\d\d\d\d\d\d}                  {%y%m%d}
        {\d\d-\d\d\d}                   {%y-%j}
        {\d\d\d\d\d}                    {%y%j}
        {--\d\d-\d\d}                   {--%m-%d}
        {--\d\d\d\d}                    {--%m%d}
        {--\d\d\d}                      {--%j}
        {---\d\d}                       {---%d}
        {\d\d\d\d-W\d\d-\d}             {%G-W%V-%u}
        {\d\d\d\dW\d\d\d}               {%GW%V%u}
        {\d\d-W\d\d-\d}                 {%g-W%V-%u}
        {\d\dW\d\d\d}                   {%gW%V%u}
        {-W\d\d-\d}                     {-W%V-%u}
        {-W\d\d\d}                      {-W%V%u}
        {-W-\d}                         {%u}
    }

    # MatchTime -- (constructed procedure)
    #
    #   Match an ISO8601 date/time string and indicate how it matched.
    #
    # Parameters:
    #   string -- String to match.
    #   fieldArray -- Name of an array in caller's scope that will receive
    #                 parsed fields of the time.
    #
    # Results:
    #   Returns 1 if the time was scanned successfully, 0 otherwise.
    #
    # Side effects:
    #   Initializes the field array.  The keys that are significant:
    #           - Any date pattern in 'DatePatterns' indicates that the
    #             corresponding value, if non-empty, contains a date string
    #             in the given format.
    #           - The patterns T, Hcolon, and Mcolon indicate a literal
    #             T preceding the time, a colon following the hour, or
    #             a colon following the minute.
    #           - %H, %M, %S, and %Z indicate the presence of the
    #             corresponding parts of the time.

    proc init {} {

        variable DatePatterns

        set cmd {regexp -expanded -nocase -- {PATTERN} $timeString ->}
        set re \(?:\(?:
        set sep {}
        foreach {regex interpretation} $DatePatterns {
            append re $sep \( $regex \)
            append cmd " " [list field($interpretation)]
            set sep |
        }
        append re \) {(T|[[:space:]]+)} \)?
        append cmd { field(T)}
        append re {(\d\d)(?:(:?)(\d\d)(?:(:?)(\d\d)))}
        append cmd { field(%H) field(Hcolon) } \
            {field(%M) field(Mcolon) field(%S)}
        append re {[[:space:]]*(Z|[-+]\d\d\d\d)?}
        append cmd { field(%Z)}
        set cmd [string map [list {{PATTERN}} [list $re]] \
                                  $cmd]

        proc MatchTime { timeString fieldArray } "
            upvar 1 \$fieldArray field
            $cmd
        "
    }
    init
    rename init {}

}

# iso8601::parse_date --
#
#       Parse an ISO8601 date/time string in an unknown variant.
#
# Parameters:
#       string -- String to parse
#       args -- Arguments as for [clock scan]; may include any of
#               the '-base', '-gmt', '-locale' or '-timezone options.
#
# Results:
#       Returns the given date in seconds from the Posix epoch.

proc iso8601::parse_date { string args } {
    variable DatePatterns
    foreach { regex interpretation } $DatePatterns {
        if { [regexp "^$regex\$" $string] } {
            return [eval [linsert $args 0 \
                              clock scan $string -format $interpretation]]
        }
    }
    return -code error "not an iso8601 date string"
}

# iso8601::parse_time --
#
#       Parse a point-in-time in ISO8601 format
#
# Parameters:
#       string -- String to parse
#       args -- Arguments as for [clock scan]; may include any of
#               the '-base', '-gmt', '-locale' or '-timezone options.
#
# Results:
#       Returns the given time in seconds from the Posix epoch.

proc iso8601::parse_time { timeString args } {
    variable DatePatterns
    MatchTime $timeString field
    set pattern {}
    foreach {regex interpretation} $DatePatterns {
        if { $field($interpretation) ne {} } {
            append pattern $interpretation
        }
    }
    append pattern $field(T)
    if { $field(%H) ne {} } {
        append pattern %H $field(Hcolon)
        if { $field(%M) ne {} } {
            append pattern %M $field(Mcolon)
            if { $field(%S) ne {} } {
                append pattern %S
            }
        }
    }
    if { $field(%Z) ne {} } {
        append pattern %Z
    }
    return [eval [linsert $args 0 clock scan $timeString -format $pattern]]
}

# The following code is taken from http://wiki.tcl.tk/13094

namespace eval rfc2822 {

    namespace export parseDate

    variable datepats {}
    
}

# AddDatePat --
#
#       Internal procedure that adds a date pattern to the pattern list
#
# Parameters:
#       wpat - Regexp pattern that matches the weekday
#       wgrp - Format group that matches the weekday
#       ypat - Regexp pattern that matches the year
#       ygrp - Format group that matches the year
#       mdpat - Regexp pattern that matches month and day
#       mdgrp - Format group that matches month and day
#       spat - Regexp pattern that matches the seconds of the minute
#       sgrp - Format group that matches the seconds of the minute
#       zpat - Regexp pattern that matches the time zone
#       zgrp - Format group that matches the time zone
#
# Results:
#       None
#
# Side effects:
#       Adds a complete regexp and a complete [clock scan] pattern to
#       'datepats'

proc rfc2822::AddDatePat { wpat wgrp ypat ygrp mdpat mdgrp 
                           spat sgrp zpat zgrp } {
        
    variable datepats
    set regexp {^[[:space:]]*}
    set pat {}
    append regexp $wpat $mdpat {[[:space:]]+} $ypat
    append pat $wgrp $mdgrp $ygrp
    append regexp {[[:space:]]+\d\d?:\d\d} $spat
    append pat { %H:%M} $sgrp
    append regexp $zpat
    append pat $zgrp
    append regexp {[[:space:]]*$}
    lappend datepats $regexp $pat
    return
}
    
# InitDatePats --
#
#       Internal rocedure that initializes the set of date patterns allowed in
#       an RFC2822 date
#
# Parameters:
#       permissible - 1 if erroneous (but common) time zones are to be
#                     allowed, 0 if they are to be rejected
#
# Results:
#       None.
#
# Side effects:

proc rfc2822::InitDatePats { permissible } {
        
    # Produce formats for the observed variants of ISO2822 dates.  Permissible
    # variants come first in the list; impermissible ones come later.
    
    # The month and day may be "%b %d" or "%d %b"
    
    foreach mdpat {{[[:alpha:]]+[[:space:]]+\d\d?} 
        {\d\d?[[:space:]]+[[:alpha:]]+}} \
        mdgrp {{%b %d} {%d %b}} \
        mdperm {0 1} {

            # The year may be two digits, or four. Four digit year is done 
            # first.
    
            foreach ypat {{\d\d\d\d} {\d\d}} ygrp {%Y %y} {
                
                # The seconds of the minute may be provided, or omitted.
                
                foreach spat {{:\d\d} {}} sgrp {:%S {}} {
                    
                    # The weekday may be provided or omitted. It is common but
                    # impermissible to omit the comma after the weekday name.
                    
                    foreach wpat {
                        {(?:Mon|T(?:ue|hu)|Wed|Fri|S(?:at|un)),[[:space:]]+}
                        {(?:Mon|T(?:ue|hu)|Wed|Fri|S(?:at|un))[[:space:]]+}
                        {}
                    } wgrp {
                        {%a, }
                        {%a }
                        {}
                    } wperm {
                        1
                        0
                        1
                    } {
                        
                        # Time zone is defined as +/- hhmm, or as a
                        # named time zone.  Other common but buggy
                        # formats are GMT+-hh:mm, a time zone name in
                        # quotation marks, and complete omission of
                        # the time zone.
                
                        foreach zpat {
                            {[[:space:]]+(?:[-+]\d\d\d\d|[[:alpha:]]+)} 
                            {[[:space:]]+GMT[-+]\d\d:?\d\d}
                            {[[:space:]]+"[[:alpha:]]+"}
                            {}
                        } zgrp {
                            { %Z}
                            { GMT%Z}
                            { "%Z"}
                            {}
                        } zperm {
                            1
                            0
                            0
                            0
                        } {
                            if { ($zperm && $wperm && $mdperm)
                                 == $permissible } {
                                AddDatePat $wpat $wgrp $ypat $ygrp \
                                    $mdpat $mdgrp \
                                    $spat $sgrp $zpat $zgrp
                            }
                        }
                    }
                }
            }
        }
    return
}

# Initialize the date patterns

namespace eval rfc2822 {
    InitDatePats 1
    InitDatePats 0
    rename AddDatePat {}
    rename InitDatePats {}
}

# rfc2822::parseDate --
#
#       Parses a date expressed in RFC2822 format
#
# Parameters:
#       date - The date to parse
#
# Results:
#       Returns the date expressed in seconds from the Epoch, or throws
#       an error if the date could not be parsed.

proc rfc2822::parseDate { date } {
    variable datepats

    # Strip comments and excess whitespace from the date field

    regsub -all -expanded {
        \(              # open parenthesis
        (:?
              [^()[.\.]]   # character other than ()\
              |\\.         # or backslash escape
        )*              # any number of times
        \)              # close paren
    } $date {} date
    set date [string trim $date]

    # Match the patterns in order of preference, returning the first success

    foreach {regexp pat} $datepats {
        if { [regexp -nocase $regexp $date] } {
            return [clock scan $date -format $pat]
        }
    }

    return -code error -errorcode {RFC2822 BADDATE} \
        "expected an RFC2822 date, got \"$date\""

}

#######################################################################

# HACK: Adding missing legacy timezones

if {[catch { clock scan msk }]} {
    lappend ::tcl::clock::LegacyTimeZone msk +0300 msd +0400
}

set debugP 0
set logFile ""

proc ::LOG {message} {
    global debugP logFile

    if {$debugP > 0} {
        puts stderr $message
    }

    if {([string first "DEBUG " $message] == 0) \
            || (![string compare $logFile ""]) \
            || ([catch { set fd [open $logFile { WRONLY CREAT APPEND }] }])} {
        return
    }

    regsub -all "\n" $message " " message

    set now [clock seconds]
    if {[set x [string first . [set host [info hostname]]]] > 0} {
        set host [string range $host 0 [expr {$x - 1}]]
    }
    catch { puts -nonewline $fd \
                 [format "%s %2d %s %s personal\[%d\]: %s\n" \
                         [clock format $now -format %b] \
                         [string trimleft [clock format $now -format %d] 0] \
                         [clock format $now -format %T] $host \
                         [expr {[pid] % 65535}] $message] }

    catch { close $fd }
}

proc ::bgerror {err} {
    global errorInfo

    ::LOG "$err\n$errorInfo"
}


set status 1

array set rssbot::lib [list lastwhen [clock seconds] lastwhat ""]

if {(([set x [lsearch -exact $argv -help]] >= 0) \
            || ([set x [lsearch -exact $argv --help]] >= 0)) \
        && (![expr {$x % 2}])} {
    puts stdout "usage: rssbot.tcl ?options...?
            -pidfile     file
            -from        jid
            -password    string
            -tls         boolean (e.g., 'true')

The file .jsendrc.tcl is consulted, e.g.,

    set args {-from fred@example.com/bedrock -password wilma}

for default values."

    set status 0
} elseif {[expr {$argc % 2}]} {
    puts stderr "usage: rssbot.tcl ?-key value?..."
} elseif {[catch {
    if {([file exists [set file .jsendrc.tcl]]) \
            || ([file exists [set file ~/.jsendrc.tcl]])} {
        set args {}

        source $file

        array set at [list -permissions 600]
        array set at [file attributes $file]

        if {([set x [lsearch -exact $args "-password"]] > 0) \
                    && (![expr {$x % 2}]) \
                    && (![string match *00 $at(-permissions)])} {
            error "file should be mode 0600"
        }

        if {[llength $args] > 0} {
            set argv [eval [list linsert $argv 0] $args]
        }
    }
} result]} {
    puts stderr "error in $file: $result"
} else {
    if {([set x [lsearch -exact $argv -debug]] >= 0) && (![expr {$x % 2}])} {
        switch -- [string tolower [lindex $argv [expr {$x + 1}]]] {
            1 - true - yes - on { set debugP 1 }
        }
    }
    if {([set x [lsearch -exact $argv -logfile]] >= 0) && (![expr {$x % 2}])} {
        set logFile [lindex $argv [expr {$x + 1}]]
    }

    if {([set x [lsearch -exact $argv "-pidfile"]] >= 0) && (![expr {$x % 2}])} {
        set fd [open [set pf [lindex $argv [expr {$x + 1}]]] \
                     { WRONLY CREAT TRUNC }]
        puts $fd [pid]
        close $fd
    }

    after idle [list rssbot::begin $argv]

    set doneP 0
    vwait doneP

    catch { file delete -- $pf }

    set status 0
}

exit $status

# vim:ft=tcl:ts=8:sw=4:sts=4:et
