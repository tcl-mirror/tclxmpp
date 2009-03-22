# poll.tcl --
#
#       This file is a part of the XMPP library. It implements HTTP-polling.
#
# Copyright (c) 2008-2009 Sergei Golovan <sgolovan@nes.ru>
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
            -opencommand        [namespace code open]       \
            -abortcommand       [namespace code abort]      \
            -closecommand       [namespace code close]      \
            -resetcommand       [namespace code reset]      \
            -flushcommand       [namespace code flush]      \
            -ipcommand          [namespace code ip]         \
            -outxmlcommand      [namespace code outXML]     \
            -outtextcommand     [namespace code outText]    \
            -openstreamcommand  [namespace code openStream] \
            -closestreamcommand [namespace code closeStream]

    if {![catch { package require tls 1.4 }]} {
        ::http::register https 443 ::tls::socket
    }

    variable debug 0
}

# ::xmpp::transport::poll::open --
#
#       Open connection to XMPP server. For HTTP-poll transport this means
#       "store poll parameters, create XML parser, and return or call back
#       with success.
#
# Arguments:
#       server                      (ignored, -url option is used) XMPP server
#                                   hostname.
#       port                        (ignored, -url option is used) XMPP server
#                                   port.
#       -url url                    (mandatory) HTTP-poll URL to request.
#       -streamheadercommand cmd    Command to call when server stream header
#                                   is parsed.
#       -streamtrailercommand cmd   Command to call when server stream trailer
#                                   is parsed.
#       -stanzacommand cmd          Command to call when top-level stream
#                                   stanza is parsed.
#       -eofcommand cmd             Command to call when server (or proxy)
#                                   breaks connection.
#       -command cmd                Command to call upon a successfull or
#                                   failed connect (for this transport failing
#                                   during connect is impossible).
#       -timeout timeout            Timeout for HTTP queries.
#       -min min                    Minimum interval between polls (in
#                                   milliseconds).
#       -max min                    Maximum interval between polls (in
#                                   milliseconds).
#       -usekeys usekeys            (default true) Use poll keys which make
#                                   connection more secure.
#       -numkeys numkeys            (default 100) Number of keys in a series.
#       -host proxyHost             Proxy hostname.
#       -port proxyPort             Proxy port.
#       -username proxyUsername     Proxy username.
#       -password proxyPassword     Proxy password.
#       -useragent proxyUseragent   Proxy useragent.
#
# Result:
#       Transport token which is to be used for communication with XMPP server.
#
# Side effects:
#       A new variable is created where polling options are stored. Also, a new
#       XML parser is created.

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
            -streamheadercommand  {set state(streamHeaderCmd)  $val}
            -streamtrailercommand {set state(streamTrailerCmd) $val}
            -stanzacommand        {set state(stanzaCmd)        $val}
            -eofcommand           {set state(eofCmd)           $val}
            -command              {set cmd                     $val}
            -timeout     -
            -min         -
            -max         -
            -url         -
            -usekeys     -
            -numkeys     {set state($key)    $val}
            -proxyfilter {set proxyFilter    $val}
            -host        {set proxyHost      $val}
            -port        {set proxyPort      $val}
            -username    {set proxyUsername  $val}
            -password    {set proxyPassword  $val}
            -useragent   {set proxyUseragent $val}
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

    if {[info exists proxyFilter]} {
        # URLmatcher is borrowed from http package.
        set URLmatcher {(?x)                    # this is _expanded_ syntax
            ^
            (?: (\w+) : ) ?                     # <protocol scheme>
            (?: //
                (?:
                    (
                        [^@/\#?]+               # <userinfo part of authority>
                    ) @
                )?
                ( [^/:\#?]+ )                   # <host part of authority>
                (?: : (\d+) )?                  # <port part of authority>
            )?
            ( / [^\#?]* (?: \? [^\#?]* )?)?     # <path> (including query)
            (?: \# (.*) )?                      # <fragment>
            $
        }

        if {[regexp -- $URLmatcher $state(-url) -> \
                       proto user host port srvurl]} {
            if {![catch {eval $proxyFilter $host} answer]} {
                foreach {phost pport proxyUsername proxyPassword} $answer {
                    break
                }
            }
        }
        
        ::http::config -proxyfilter $proxyFilter
    }

    if {[info exists proxyHost] && [info exists proxyPort]} {
        ::http::config -proxyhost $proxyHost -proxyport $proxyPort
    }

    if {[info exists proxyUsername] && [info exists proxyPassword]} {
        set auth \
            [base64::encode \
                    [encoding convertto $proxyUsername:$proxyPassword]]
        set state(proxyAuth) [list Proxy-Authorization "Basic $auth"]
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

# ::xmpp::transport::poll::outText --
#
#       Send text to XMPP server.
#
# Arguments:
#       token           Transport token.
#       text            Text to send.
#
# Result:
#       Empty string.
#
# Side effects:
#       Sending text to the server is scheduled.

proc ::xmpp::transport::poll::outText {token text} {
    variable $token
    upvar 0 $token state

    if {![info exists state(wait)]} {
        return -1
    }

    switch -- $state(wait) {
        disconnected  -
        waiting       -
        disconnecting {
            # TODO
            return -1
        }
        default {
            Poll $token $text
        }
    }
    # TODO
    return [string bytelength $text]
}

# ::xmpp::transport::poll::outXML --
#
#       Send XML element to XMPP server.
#
# Arguments:
#       token           Transport token.
#       xml             XML to send.
#
# Result:
#       Empty string.
#
# Side effects:
#       Sending XML to the server is scheduled.

proc ::xmpp::transport::poll::outXML {token xml} {
    return [outText $token [::xmpp::xml::toText $xml]]
}

# ::xmpp::transport::poll::openStream --
#
#       Send XMPP stream header to XMPP server.
#
# Arguments:
#       token           Transport token.
#       server          XMPP server.
#       args            Arguments for [::xmpp::xml::streamHeader].
#
# Result:
#       Empty string.
#
# Side effects:
#       Sending string to the server is scheduled.

proc ::xmpp::transport::poll::openStream {token server args} {
    return [outText $token \
                    [eval [list ::xmpp::xml::streamHeader $server] $args]]
}

# ::xmpp::transport::poll::closeStream --
#
#       Send XMPP stream trailer to XMPP server and start disconnecting
#       procedure.
#
# Arguments:
#       token           Transport token.
#
# Result:
#       Empty string.
#
# Side effects:
#       Sending stream trailer to the server is scheduled.

proc ::xmpp::transport::poll::closeStream {token} {
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

# ::xmpp::transport::poll::flush --
#
#       Flush XMPP channel.
#
# Arguments:
#       token           Transport token.
#
# Result:
#       Empty string.
#
# Side effects:
#       Pending data is sent to the server.

proc ::xmpp::transport::poll::flush {token} {
    # TODO
}

# ::xmpp::transport::poll::ip --
#
#       Return IP of an outgoing socket.
#
# Arguments:
#       token           Transport token.
#
# Result:
#       Empty string (until really implemented).
#
# Side effects:
#       None.

proc ::xmpp::transport::poll::ip {token} {
    variable $token
    upvar 0 $token state

    # TODO
    return ""
}

# ::xmpp::transport::poll::close --
#
#       Close XMPP channel.
#
# Arguments:
#       token           Transport token.
#
# Result:
#       Empty string.
#
# Side effects:
#       Transport token and XML parser are destroyed.

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

# ::xmpp::transport::poll::reset --
#
#       Reset XMPP stream.
#
# Arguments:
#       token           Transport token.
#
# Result:
#       Empty string.
#
# Side effects:
#       XML parser is reset.

proc ::xmpp::transport::poll::reset {token} {
    variable $token
    upvar 0 $token state

    ::xmpp::xml::reset $state(parser)
    return
}

# ::xmpp::transport::poll::InText --
#
#       A helper procedure which is called when a new portion of data is
#       received from XMPP server. It feeds XML parser with this data.
#
# Arguments:
#       token           Transport token.
#       text            Text to parse.
#
# Result:
#       Empty string.
#
# Side effects:
#       The text is parsed and if it completes top-level stanza then an
#       appropriate callback is invoked.

proc ::xmpp::transport::poll::InText {token text} {
    variable $token
    upvar 0 $token state

    ::xmpp::xml::parser $state(parser) parse $text

    return
}

# ::xmpp::transport::poll::InXML --
#
#       A helper procedure which is called when a new XML stanza is parsed.
#       It then calls a specified command as an idle callback.
#
# Arguments:
#       cmd             Command to call.
#       xml             Stanza to pass to the command.
#
# Result:
#       Empty string.
#
# Side effects:
#       After entering event loop the spaecified command is called.

proc ::xmpp::transport::poll::InXML {cmd xml} {
    after idle $cmd [list $xml]
    return
}

# ::xmpp::transport::poll::InEmpty --
#
#       A helper procedure which is called when XMPP stream is finished.
#       It then calls a specified command as an idle callback.
#
# Arguments:
#       cmd             Command to call.
#
# Result:
#       Empty string.
#
# Side effects:
#       After entering event loop the spaecified command is called.

proc ::xmpp::transport::poll::InEmpty {cmd} {
    after idle $cmd
    return
}

# ::xmpp::transport::poll::Poll --
#
#       Schedule HTTP-polling procedure to output given text.
#
# Arguments:
#       token               Tranport token.
#       text                Text to output.
#
# Result:
#       Empty string.
#
# Side effects:
#       If there's no request which is waited for then a new request is sent,
#       otherwise a new call to [Poll] is scheduled.

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

# ::xmpp::transport::poll::ProcessReply --
#
#       Process HTTP-poll reply from the XMPP server.
#
# Arguments:
#       token               Tranport token.
#       try                 Number of the previous requests of the same query.
#       query               Query string.
#       httpToken           HTTP token to get server answer.
#
# Result:
#       Empty string.
#
# Side effects:
#       If query failed then it is retried (not more than thrice), otherwise the
#       answer is received and pushed to XML parser.

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

    Debug $token 2 $httpState(meta)

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

# ::xmpp::transport::poll::GetURL --
#
#       Request HTTP-poll URL.
#
# Arguments:
#       token               Transport token.
#       try                 Number of previous requests of the same query
#                           (sometimes query fails because of proxy errors, so
#                           it's better to try once more).
#       query               Query to send to the server.
#
# Result:
#       Empty string.
#
# Side effects:
#       HTTP-poll request is sent.

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

# ::xmpp::transport::poll::SetWait --
#
#       Set polling state for a given connection (if it exists) and if the
#       state is "disconnected" then cancel future polling attempts.
#
# Arguments:
#       token           Tranport token.
#       opt             State name ("polling", "waiting", "connected",
#                       "disconnecting", "disconnected").
#
# Result:
#       Empty string.
#
# Side effects:
#       Polling state is changed. If it becomes "disconnected" then the next
#       polling attempt is canceled.

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

    return
}

# ::xmpp::transport::poll::GenKeys --
#
#       Generate a sequence of security keys (see XEP-0025 for details).
#
# Arguments:
#       numKeys             Number of keys to generate.
#
# Result:
#       List of keys.
#
# Side effects:
#       None.

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
#       Print debug information.
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
