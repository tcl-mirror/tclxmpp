# poll.tcl --
#
#       This file is a part of the XMPP library. It implements HTTP-polling.
#
# Copyright (c) 2008 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require sha1
package require http

package require xmpp::transport
package require xmpp::xml

package provide xmpp::transport::poll 0.1

namespace eval ::xmpp::transport::poll {
    namespace export open abort close reset flush ip outXML outText \
                     openStream closeStream

    ::xmpp::transport::register poll \
            -openCommand        [namespace code open]       \
            -abortCommand       [namespace code abort]      \
            -closeCommand       [namespace code close]      \
            -resetCommand       [namespace code reset]      \
            -flushCommand       [namespace code flush]      \
            -ipCommand          [namespace code ip]      \
            -outXMLCommand      [namespace code outXML]     \
            -outTextCommand     [namespace code outText]    \
            -openStreamCommand  [namespace code openStream] \
            -closeStreamCommand [namespace code closeStream]

    if {![catch { package require tls 1.4 }]} {
        ::http::register https 443 ::tls::socket
    }

    variable debug 0
}

proc ::xmpp::transport::poll::open {server port args} {
    variable id

    if {![info exists id]} {
        set id 0
    }

    set token [namespace current]::[incr id]
    variable $token
    upvar 0 $token state

    set state(transport) poll

    set state(streamHeaderCmd)  #
    set state(streamTrailerCmd) #
    set state(stanzaCmd)        #
    set state(eofCmd)           #
    set state(-timeout)         0
    set state(-min)             10000
    set state(-max)             60000
    set state(-url)             ""
    set state(-usekeys)         1
    set state(-numkeys)         100

    foreach {key val} $args {
        switch -- $key {
            -command              {set cmd                     $val}
            -streamHeaderCommand  {set state(streamHeaderCmd)  $val}
            -streamTrailerCommand {set state(streamTrailerCmd) $val}
            -stanzaCommand        {set state(stanzaCmd)        $val}
            -eofCommand           {set state(eofCmd)           $val}
            -timeout        -
            -min            -
            -max            -
            -url            -
            -usekeys        -
            -numkeys        {set state($key)    $val}
            -proxyHost      {set proxyHost      $val}
            -proxyPort      {set proxyPort      $val}
            -proxyUsername  {set proxyUsername  $val}
            -proxyPassword  {set proxyPassword  $val}
            -proxyUseragent {set proxyUseragent $val}
        }
    }

    set state(int)       $state(-min)
    set state(outdata)   ""
    set state(sesskey)   0
    set state(id)        ""
    set state(keys)      {}
    set state(proxyAuth) {}
    set state(wait)      disconnected

    if {[info exists proxyUseragent]} {
        ::http::config -useragent $proxyUseragent
    }

    if {[info exists proxyHost] && [info exists proxyPort]} {
        ::http::config -proxyhost $proxyHost -proxyport $proxyPort

        if {[info exists proxyUsername] && [info exists proxyPassword]} {
            set auth \
                [base64::encode \
                        [encoding convertto $proxyUsername:$proxyPassword]]
            set state(proxyAuth) [list Proxy-Authorization "Basic $auth"]
        }
    }

    if {$state(-usekeys)} {
        Debug $token 2 "generating keys"
        set state(keys) [GenKeys $state(-numkeys)]
    }

    set state(parser) \
        [::xmpp::xml::new \
                [namespace code [list InXML $state(streamHeaderCmd)]] \
                [namespace code [list InEmpty $state(streamTrailerCmd)]] \
                [namespace code [list InXML $state(stanzaCmd)]]]

    SetWait $token connected

    if {[info exists cmd]} {
        # Asynchronous mode is almost synchronous
        after idle $cmd [list ok $token]
    }

    return $token
}

proc ::xmpp::transport::poll::outText {token text} {
    variable $token
    upvar 0 $token state

    if {![info exists state(wait)]} {
        return
    }

    switch -- $state(wait) {
        disconnected  -
        waiting       -
        disconnecting {
            # TODO
        }
        default {
            Poll $token $text
        }
    }
}

proc ::xmpp::transport::poll::outXML {token xml} {
    return [outText $token [::xmpp::xml::toText $xml]]
}

proc ::xmpp::transport::poll::openStream {token server args} {
    return [outText $token \
                    [eval [list ::xmpp::xml::streamHeader $server] $args]]
}

proc ::xmpp::transport::poll::closeStream {token args} {
    variable $token
    upvar 0 $token state

    set len [outText $token [::xmpp::xml::streamTrailer]]

    switch -- $state(wait) {
        disconnected -
        waiting {}
        polling {
            SetWait $token waiting
        }
        default {
            SetWait $token disconnecting
        }
    }

    # TODO
    if {0} {
        while {[info exists state(wait)] && \
                            ![string equal $state(wait) disconnected]} {
            vwait $token\(wait)
        }
    }

    return $len
}

proc ::xmpp::transport::poll::flush {token} {
    # TODO
}

proc ::xmpp::transport::tcp::ip {token} {
    variable $token
    upvar 0 $token state

    return ""
}

proc ::xmpp::transport::poll::close {token} {
    variable $token
    upvar 0 $token state

    if {![info exists state(wait)]} {
        return
    }

    SetWait $token disconnected

    if {[info exists state(parser)]} {
        ::xmpp::xml::free $state(parser)
    }

    catch {unset state}
    return
}

proc ::xmpp::transport::poll::reset {token} {
    variable $token
    upvar 0 $token state

    ::xmpp::xml::reset $state(parser)
}

proc ::xmpp::transport::poll::InText {token msg} {
    variable $token
    upvar 0 $token state

    ::xmpp::xml::parser $state(parser) parse $msg

    return
}

proc ::xmpp::transport::poll::InXML {cmd xml} {
    after idle $cmd [list $xml]
}

proc ::xmpp::transport::poll::InEmpty {cmd} {
    after idle $cmd
}

######################################################################

proc ::xmpp::transport::poll::SetWait {token opt} {
    variable $token
    upvar 0 $token state

    if {![info exists state(wait)]} {
        return
    }

    set state(wait) $opt

    switch -- $opt {
        disconnected {
            after cancel $state(id)
        }
    }
}

proc ::xmpp::transport::poll::ProcessReply {token try query httpToken} {
    variable $token
    upvar 0 $token state

    if {![info exists state(wait)]} {
        # A reply for an already disconnected connection
        return
    }

    upvar #0 $httpToken httpState

    if {[::http::ncode $httpToken] != 200} {
        Debug $token 1 "HTTP returned [::http::ncode $httpToken]\
                                      $httpState(status)"

        if {$try < 3} {
            GetURL $token [incr try] $query
        } else {
            SetWait $token disconnected
            InEmpty $state(eofCmd)
        }
        ::http::cleanup $httpToken
        return
    }

    foreach {name value} $httpState(meta) {
        if {[string equal -nocase $name Set-Cookie] && \
                            [regexp {^ID=([^;]*);?} $value -> match]} {
            Debug $token 2 "Set-Cookie: $value -> $match"

            if {[string match *:0 $match] || [string match *%3A0 $match]} {
                Debug $token 1 "Cookie Error"

                SetWait $token disconnected
                InEmpty $state(eofCmd)

                ::http::cleanup $httpToken
                return
            }

            set state(sesskey) $match
            break
        }
    }

    set inmsg [encoding convertfrom utf-8 $httpState(body)]
    ::http::cleanup $httpToken

    Debug $token 2 '$inmsg'

    if {[string length $inmsg] > 5 } {
        set state(int) [expr {$state(int) / 2}]
        if {$state(int) < $state(-min)} {
            set state(int) $state(-min)
        }
    } else {
        set state(int) [expr {$state(int) * 6 / 5}]
        if {$state(int) > $state(-max)} {
            set state(int) $state(-max)
        }
    }

    InText $token $inmsg

    switch -- $state(wait) {
        waiting {
            SetWait $token disconnecting
        }
        polling {
            SetWait $token connected
        }
    }
}

proc ::xmpp::transport::poll::Poll {token text} {
    variable $token
    upvar 0 $token state

    Debug $token 2 '$text'

    if {![info exists state(wait)]} {
        # Trying to poll an already disconnected connection
        return
    }

    append state(outdata) $text

    switch -- $state(wait) {
        disconnected {
            Debug $token 2 DISCONNECTED

            return
        }
        disconnecting {
            Debug $token 2 DISCONNECTING

            if {[string equal $state(outdata) ""]} {
                SetWait $token disconnected
                return
            }
        }
        waiting -
        polling {
            Debug $token 2 RESCHEDULING

            after cancel $state(id)

            Debug $token 2 $state(int)

            set state(id) \
                [after $state(int) [namespace code [list Poll $token ""]]]
            return
        }
    }

    if {$state(-usekeys)} {
        # regenerate
        set firstkey [lindex $state(keys) end]
        set secondkey ""
        if {[llength $state(keys)] == 1} {
            Debug $token 2 "regenerating keys"
            set state(keys) [GenKeys $state(-numkeys)]
            set secondkey [lindex $state(keys) end]
        }
        set l [llength $state(keys)]
        set state(keys) [lrange $state(keys) 0 [expr {$l - 2}]]

        if {[string length $firstkey]} {
            set firstkey ";$firstkey"
        }

        if {[string length $secondkey]} {
            set secondkey ";$secondkey"
        }

        set query "$state(sesskey)$firstkey$secondkey,$state(outdata)"
    } else {
        set query "$state(sesskey),$state(outdata)"
    }

    switch -- $state(wait) {
        disconnecting {
            SetWait $token waiting
        }
        default {
            SetWait $token polling
        }
    }

    Debug $token 2 "query: '$query'"

    GetURL $token 0 [encoding convertto utf-8 $query]

    set state(outdata) ""

    after cancel $state(id)

    Debug $token 2 $state(int)

    set state(id) \
        [after $state(int) [namespace code [list Poll $token ""]]]
    return
}

proc ::xmpp::transport::poll::GetURL {token try query} {
    variable $token
    upvar 0 $token state

    Debug $token 2 $try

    ::http::geturl $state(-url) \
                   -binary  1 \
                   -headers $state(proxyAuth) \
                   -query   $query \
                   -timeout $state(-timeout) \
                   -command [namespace code [list ProcessReply $token \
                                                               $try \
                                                               $query]]
    return
}

proc ::xmpp::transport::poll::GenKeys {numKeys} {
    set seed [expr {round(1000000000 * rand())}]
    set oldKey $seed
    set keys {}

    while {$numKeys > 0} {
        set nextKey [base64::encode [binary format H40 [sha1::sha1 $oldKey]]]
        # skip the initial seed
        lappend keys $nextKey
        set oldKey $nextKey
        incr numKeys -1
    }
    return $keys
}

# ::xmpp::transport::poll::Debug --
#
#       Prints debug information.
#
# Arguments:
#       token   Transport token.
#       level   Debug level.
#       str     Debug message.
#
# Result:
#       An empty string.
#
# Side effects:
#       A debug message is printed to the console if the value of
#       ::xmpp::transport::poll::debug variable is not less than num.

proc ::xmpp::transport::poll::Debug {token level str} {
    variable debug

    if {$debug >= $level} {
        puts "[lindex [info level -1] 0] $token: $str"
    }

    return
}

# vim:ts=8:sw=4:sts=4:et
