# xml.tcl --
#
#       This file is part of the XMPP library. It defines procedures which
#       wrap XML parser. These procedures are called by functions in XMPP
#       library, and they in turn call the TclXML or tDOM library functions.
#
# Copyright (c) 2008 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require msgcat

if {[catch {package require tdom 0.8}]} {
    package require -exact xml 2.0
}

package provide xmpp::xml 0.1

namespace eval ::xmpp::xml {
    namespace export new free parser reset toText create split merge \
                     isAttr getAttr getCdata getFirstCdata getNextCdata \
                     streamHeader streamTrailer parseData lang
}

# ::xmpp::xml::new --
#
#       Creates new wrapper over an XML parser.
#
# Arguments:
#       streamHeaderCmd     A command which is to be called when XMPP stream
#                           header is received.
#       streamTrailerCmd    A command which is to be called when XMPP stream
#                           trailer is receoved.
#       stanzaCmd           A command which is to be called when XMPP stream
#                           stanza is received.
# Results:
#       A new parser token (a state array name).
#
# Side effects:
#       A new XML parser is created.

proc ::xmpp::xml::new {streamHeaderCmd streamTrailerCmd stanzaCmd} {
    variable id

    if {![info exists id]} {
        set id 0
    } else {
        incr id
    }

    set token [namespace current]::parser#$id
    variable $token
    upvar 0 $token state

    set state(streamHeaderCmd)  $streamHeaderCmd
    set state(streamTrailerCmd) $streamTrailerCmd
    set state(stanzaCmd)        $stanzaCmd

    set state(parser) \
        [::xml::parser parser#$id \
             -final 0 \
             -elementstartcommand  [namespace code [list ElementStart $token]] \
             -elementendcommand    [namespace code [list ElementEnd   $token]] \
             -characterdatacommand [namespace code [list ElementCdata $token]]]

    if {[llength [info commands ::$state(parser)]] == 0} {
        set state(parser) [namespace current]::$state(parser)
    }

    set state(stack) {}
    set state(namespace) {{{} {} xml xml}}

    return $token
}

# ::xmpp::xml::free --
#
#       Frees a previously created wrapper over an XML parser.
#
# Arguments:
#       token               A previously created wrapper token.
#
# Results:
#       An empty string.
#
# Side effects:
#       An existing XML parser is destroyed.

proc ::xmpp::xml::free {token} {
    variable $token
    upvar 0 $token state

    if {![info exists state(parser)]} {
        return -code error \
               -errorinfo [::msgcat::mc "Parser \"%s\" doesn't exist" $token]
    }

    $state(parser) free
    unset state
    return
}

# ::xmpp::xml::parser --
#
#       Calls wrapped XML parser.
#
# Arguments:
#       token               A wrapper token.
#       command             An XML parser command (configure, parse, etc.).
#       args                Arguments for a given command.
#
# Results:
#       An empty string.
#
# Side effects:
#       An XML parser invokes a series of callbacks.

proc ::xmpp::xml::parser {token command args} {
    variable $token
    upvar 0 $token state

    if {![info exists state(parser)]} {
        return -code error \
               -errorinfo [::msgcat::mc "Parser \"%s\" doesn't exist" $token]
    }

    # TODO: catch and process errors
    return [uplevel 1 [list $state(parser) $command] $args]
}

# ::xmpp::xml::reset --
#
#       Resets wrapped XML parser and internal stack.
#
# Arguments:
#       token               A wrapper token.
#
# Results:
#       An empty string.
#
# Side effects:
#       A wrapped parser is reset.

proc ::xmpp::xml::reset {token} {
    variable $token
    upvar 0 $token state

    if {![info exists state(parser)]} {
        return -code error \
               -errorinfo [::msgcat::mc "Parser \"%s\" doesn't exist" $token]
    }

    $state(parser) reset
    catch {$state(parser) configure -namespace 0}
    $state(parser) configure \
        -final 0 \
        -elementstartcommand  [namespace code [list ElementStart $token]] \
        -elementendcommand    [namespace code [list ElementEnd   $token]] \
        -characterdatacommand [namespace code [list ElementCdata $token]]

    set state(stack) {}
    set state(namespace) {{{} {} xml xml}}
    return
}

# ::xmpp::xml::toText --
#
#       Creates textual representation from XML data.
#
# Arguments:
#       xmldata         A parsed (or created by create) XML element.
#       pxmlns          Optional. XMLNS of a parent XML element.
#
# Results:
#       A converted raw XML data.
#
# Side effects:
#       None.

proc ::xmpp::xml::toText {xmldata {pxmlns ""}} {
    set retext ""

    set tag    [lindex $xmldata 0]
    set xmlns  [lindex $xmldata 1]
    set attrs  [lindex $xmldata 2]
    set subels [lindex $xmldata 3]
    set cdata  [lindex $xmldata 4]

    append retext "<$tag"
    if {![string equal $xmlns ""] && ![string equal $xmlns $pxmlns]} {
        append retext " xmlns='[Escape $xmlns]'"
        set pxmlns $xmlns
    }
    foreach {attr value} $attrs {
        append retext " $attr='[Escape $value]'"
    }
    if {[string equal $cdata ""] && [llength $subels] == 0} {
        append retext "/>"
        return $retext
    } else {
        append retext ">"
    }

    append retext [Escape $cdata]

    foreach subdata $subels {
        append retext [toText $subdata $pxmlns]
        append retext [Escape [lindex $subdata 5]]
    }

    append retext "</$tag>"
    return $retext
}

# ::xmpp::xml::toTabbedText --
#
#       Creates pretty-printed textual representation from XML data. The XML
#       must satisfy the following condition: it must contain either a single
#       CDATA element or a list of subelements. Mixing CDATA and subelements
#       is not allowed. This procedure may be useful for saving XML into
#       files.
#
# Arguments:
#       xmldata         A parsed (or created by create) XML element.
#       pxmlns          Optional. XMLNS of a parent XML element.
#
# Results:
#       A converted raw XML data.
#
# Side effects:
#       None.

proc ::xmpp::xml::toTabbedText {xmldata {pxmlns ""}} {
    return [toText [ReplaceCdata $xmldata 0] $pxmlns]
}

# ::xmpp::xml::ReplaceCdata --
#
#       Replace character data in XML element to a mix of tabs and linefeeds
#       to make its textual representation look pretty. This procedure distorts
#       XML element if it has subelements and CDATA simultaneously.
#
# Arguments:
#       xmldata     A parsed (or created by create) XML element.
#       level       number of tabulation characters to add before the element.
#
# Result:
#       XML element with CDATA sections replaced by tabs (except if CDATA is
#       a unique subelement).
#
# Side effects:
#       None.

proc ::xmpp::xml::ReplaceCdata {xmldata level} {
    set tag    [lindex $xmldata 0]
    set xmlns  [lindex $xmldata 1]
    set attrs  [lindex $xmldata 2]
    set subels [lindex $xmldata 3]
    set cdata1 [lindex $xmldata 4]
    set cdata2 [lindex $xmldata 5]

    if {[llength $subels] == 0} {
        return [lreplace $xmldata 5 5 \n[string repeat \t $level]]
    } else {
        set cdata1 \n[string repeat \t [expr {$level+1}]]
        set cdata2 \n[string repeat \t $level]
        set newsubels {}
        foreach subel [lrange $subels 0 end-1] {
            lappend newsubels [ReplaceCdata $subel [expr {$level+1}]]
        }
        lappend newsubels [ReplaceCdata [lindex $subels end] $level]

        return [list $tag $xmlns $attrs $newsubels $cdata1 $cdata2]
    }
}

# ::xmpp::xml::create --
#
#       Creates XML data for an element.
#
# Arguments:
#       tag                 An XML element name.
#       -xmlns xmlns        An element XMLNS (optional, default is empty which
#                           means inherited from a parent element).
#       -attrs attrlist     A list {attr1 value1 attr2 value2 ...} of
#                           attribute/value pairs (optional, default is no
#                           attributes). Attribute list must not contain xmlns.
#       -cdata cdata        CData of an element. It is appended after
#                           the latest subelement (optional, defaoult is empty
#                           CData).
#       -subelement el      A subelement to add after the latest CData or
#                           already added subelement (optional, default is no
#                           subelements).
#       -subelements ellist A list of subelements to add (optional, default is
#                           no subelements).
#
# Results:
#       A created XML element data.
#
# Side effects:
#       None.

proc ::xmpp::xml::create {tag args} {
    set xmlns  ""
    set attrs  {}
    set cdata  ""
    set subels {}

    foreach {key val} $args {
        switch -- $key {
            -xmlns {set xmlns $val}
        }
    }
    foreach {key val} $args {
        switch -- $key {
            -xmlns {}
            -attrs {
                foreach {attr value} $val {
                    if {[string equal $attr xmlns]} {
                        return -code error \
                               -errorinfo \
                                    [::msgcat::mc \
                                            "Illegal attribute \"xmlns\".\
                                             Use -xmlns option"]
                    }
                    lappend attrs $attr $value
                }
            }
            -cdata {
                if {[llength $subels] == 0} {
                    append cdata $val
                } else {
                    set tail [lindex $subels end]
                    set ncdata [lindex $tail 5]$val
                    set subels \
                        [lreplace $subels end end [lreplace $tail 5 5 $ncdata]]
                }
            }
            -subelement  {
                if {[llength $val] > 0} {
                    if {[string equal [lindex $val 1] ""]} {
                        lappend subels [lreplace $val 1 1 $xmlns]
                    } else {
                        lappend subels $val
                    }
                }
            }
            -subelements {
                foreach subel $val {
                    if {[llength $subel] > 0} {
                        if {[string equal [lindex $subel 1] ""]} {
                            lappend subels [lreplace $subel 1 1 $xmlns]
                        } else {
                            lappend subels $subel
                        }
                    }
                }
            }
            default {
                return -code error \
                       -errorinfo [::msgcat::mc "Invalid option \"%s\"" $key]
            }
        }
    }

    set retext [list $tag $xmlns $attrs $subels $cdata ""]

    return $retext
}

# ::xmpp::xml::split --
#
#       Splits the given xmldata into 5 variables.
#
# Arguments:
#       xmldata         A parsed XML element.
#       tagVar          A variable for element name.
#       xmlnsVar        A variable for element XMLNS.
#       attrsVar        A variable for element attributes.
#       cdataVar        A variable for element CDATA.
#       subelsVar       A variable for subelements.
#       nextCdataVar    (optional) A variable for CDATA just after XML element.
#                       This variable will always be empty for an outmost
#                       element.
#
# Results:
#       An empty string.
#
# Side effects:
#       Five or six variables are assigned.

proc ::xmpp::xml::split {xmldata tagVar xmlnsVar attrsVar cdataVar \
                         subelsVar {nextCdataVar ""}} {
    upvar 1 $tagVar tag $xmlnsVar xmlns $attrsVar attrs $cdataVar cdata \
            $subelsVar subels
    set tag    [lindex $xmldata 0]
    set xmlns  [lindex $xmldata 1]
    set attrs  [lindex $xmldata 2]
    set subels [lindex $xmldata 3]
    set cdata  [lindex $xmldata 4]

    if {![string equal $nextCdataVar ""]} {
        upvar 1 $nextCdataVar nextCdata
        set nextCdata [lindex $xmldata 5]
    }

    return
}

# ::xmpp::xml::merge --
#
#       Merges the given data from 5 variables to XML element. The correctness
#       of data isn't checked. Since it's very easy to get inconsistent cdata
#       this procedure is mainly useful if one wants to change XMLNS or
#       attributes.
#
# Arguments:
#       tag             An element name.
#       xmlns           An element XMLNS.
#       attrs           An element attributes.
#       cdata           An element CDATA.
#       subels          Subelements.
#       nextCdata       (optional) A next CDATA.
#
# Results:
#       A merged XML element.
#
# Side effects:
#       None.

proc ::xmpp::xml::merge {tag xmlns attrs cdata subels {nextCdata ""}} {
    return [list $tag $xmlns $attrs $subels $cdata $nextCdata]
}

# ::xmpp::xml::isAttr --
#
#       Returns 1, or 0, depending on if the attribute exists in attribute
#       list or not.
#
# Arguments:
#       attrList        A list of attribute-value pairs.
#       attrName        A name of attribute to check.
#
# Results:
#       1 if the list contains a requested attribute, or 0 otherwise.
#
# Side effects:
#       None.

proc ::xmpp::xml::isAttr {attrList attrName} {
    foreach {attr val} $attrList {
        if {[string equal $attr $attrName]} {
            return 1
        }
    }
    return 0
}

# ::xmpp::xml::getAttr --
#
#       Returns the value of the last given attribute from attribute list.
#
# Arguments:
#       attrList        A list of attribute-value pairs.
#       attrName        A name of attribute to get.
#       fallback        (optional, defaults to "") A returned value in case
#                       when attribute is missing
#
# Results:
#       An attribute value or a fallback value if the list doesn't
#       contain a requested attribute.
#
# Side effects:
#       None.

proc ::xmpp::xml::getAttr {attrList attrName {fallback ""}} {
    set res $fallback
    foreach {attr val} $attrList {
        if {[string equal $attr $attrName]} {
            set res $val
        }
    }
    return $res
}

# ::xmpp::xml::getCdata --
#
#       Returns all element's CDATA chunks concatenated.
#
# Arguments:
#       xmldata             A parsed XML element.
#
# Results:
#       An element CDATA.
#
# Side effects:
#       None.

proc ::xmpp::xml::getCdata {xmldata} {
    set cdata [lindex $xmldata 4]
    foreach subel [lindex $xmldata 3] {
        append cdata [lindex $subel 5]
    }
    return $cdata
}

# ::xmpp::xml::getFirstCdata --
#
#       Returns element's CDATA chunk which is located before the first
#       subelement.
#
# Arguments:
#       xmldata             A parsed XML element.
#
# Results:
#       A CDATA chunk which goes before the first subelement.
#
# Side effects:
#       None.

proc ::xmpp::xml::getFirstCdata {xmldata} {
    return [lindex $xmldata 4]
}

# ::xmpp::xml::getNextCdata --
#
#       Returns parent's CDATA chunk which is located after the given XML
#       element.
#
# Arguments:
#       xmldata             A parsed XML element.
#
# Results:
#       A parent's CDATA chunk which goes after the specified XML element.
#
# Side effects:
#       None.

proc ::xmpp::xml::getNextCdata {xmldata} {
    return [lindex $xmldata 5]
}

# ::xmpp::xml::streamHeader --
#
#       Returns XMPP stream header.
#
# Arguments:
#       to                  A peer's (server's) JID.
#       -xmlns:stream uri   xmlns:stream attribute
#       -xmlns uri          xmlns attribute
#       -xml:lang lang      xml:lang attribute (optional)
#       -version ver        XMPP version attribute (optional)
#
# Results:
#       An XMPP stream header.
#
# Side effects:
#       None.

proc ::xmpp::xml::streamHeader {to args} {
    if {[isAttr $args -xmlns:stream]} {
        set xmlns_stream [getAttr $args -xmlns:stream]
    } else {
        return -code error \
               -errorinfo [::msgcat::mc "Missing option \"%s\"" -xmlns:stream]
    }

    if {[isAttr $args -xmlns]} {
        set xmlns [getAttr $args -xmlns]
    } else {
        return -code error \
               -errorinfo [::msgcat::mc "Missing option \"%s\"" -xmlns]
    }

    set retext "<stream:stream xmlns:stream='[Escape $xmlns_stream]'\
                xmlns='[Escape $xmlns]' to='[Escape $to]'"

    foreach {key val} $args {
        switch -- $key {
            -xml:lang {
                append retext " xml:lang='[Escape $val]'"
            }
            -version {
                append retext " version='[Escape $val]'"
            }
            -xmlns:stream -
            -xmlns {}
            default {
                return -code error \
                       -errorinfo [::msgcat::mc "Invalid option \"%s\"" $key]
            }
        }
    }
    append retext ">"
    return $retext
}

# ::xmpp::xml::streamTrailer --
#
#       Returns XMPP stream trailer.
#
# Arguments:
#       None.
#
# Results:
#       An XMPP stream trailer.
#
# Side effects:
#       None.

proc ::xmpp::xml::streamTrailer {} {
    return "</stream:stream>"
}

# ::xmpp::xml::parseData --
#       Parse XML data.
#
# Arguments:
#       data            XML data to parse.
#       stanzaCmd       (optional) Callback to invoke on every outmost XML
#                       stanza. If empty then list of all parsed XML stanzas
#                       is returned.
#
# Result:
#       Empty string or parsed XML.
#
# Side effects:
#       Side effects from stanzaCmd.

proc ::xmpp::xml::parseData {data {stanzaCmd ""}} {
    set token [new # # $stanzaCmd]
    variable $token
    upvar 0 $token state

    # HACK
    if {[string equal $stanzaCmd ""]} {
        set state(stanzaCmd) [namespace code [list ParseDataAux $token]]
    }
    set state(XML) {}
    # HACK to move declaration out from file tag
    regexp {(^\s*<\?([^?]|\?[^>])*\?>)?(.*)$} $data -> header _ data
    parser $token parse "$header\n<tag>$data</tag>"
    set xml $state(XML)
    free $token
    return $xml
}

proc ::xmpp:::xml::ParseDataAux {token xmlElement} {
    variable $token
    upvar 0 $token state

    lappend state(XML) $xmlElement
}

# ::xmpp::xml::lang --
#
#       Construct xml:lang attribute from msgcat preferences.
#
# Arguments:
#       None.
#
# Result:
#       Either language code (en, ru, es etc.) or language code joined with
#       country code (en-US, ru-RU, uk-UA etc.) depending on msgcat
#       preferences.
#
# Side effects:
#       None.

proc ::xmpp::xml::lang {} {
    set prefs [::msgcat::mcpreferences]
    while {[string equal [lindex $prefs end] ""]} {
        set prefs [lreplace $prefs end end]
    }

    set lang [lindex $prefs end]

    switch -- $lang {
        "" -
        c  -
        posix {
            return en
        }
    }

    set lang2 [lindex $prefs end-1]

    if {[regexp {^([A-Za-z]+)_([0-9A-Za-z]+)} $lang2 -> l1 l2]} {
        return [string tolower $l1]-[string toupper $l2]
    } else {
        return $lang
    }
}

# ::xmpp::xml::Escape --
#
#       Escapes predefined XML entities and forbidden space characters.
#
# Arguments:
#       text                Unescaped text.
#
# Results:
#       A string where forbidden space characters are replaced by spaces
#       and symbols which correspond to predefined XML entities are
#       replaced by them.
#
# Side effects:
#       None.

proc ::xmpp::xml::Escape {text} {
    return [string map {& &amp; < &lt; > &gt; \" &quot; ' &apos;
                        \x00 " " \x01 " " \x02 " " \x03 " "
                        \x04 " " \x05 " " \x06 " " \x07 " "
                        \x08 " "                   \x0B " "
                        \x0C " "          \x0E " " \x0F " "
                        \x10 " " \x11 " " \x12 " " \x13 " "
                        \x14 " " \x15 " " \x16 " " \x17 " "
                        \x18 " " \x19 " " \x1A " " \x1B " "
                        \x1C " " \x1D " " \x1E " " \x1F " "} $text]
}

# ::xmpp::xml::ElementStart --
#
#       A callback procedure which is called by a SAX parser when it finds
#       an XML element start.
#
# Arguments:
#       token               A wrapper token.
#       tag                 A name of the current element. If tDOM is used then
#                           it contains XMLNS prepended.
#       attrs               Attributes list.
#       -namespace xmlns    An XMLNS if TclXML tclparser is used.
#
# Results:
#       An empty string.
#
# Side effects:
#       If the current element is a outmost one then stream start command is
#       called. The current element is added to an XML elements stack.

proc ::xmpp::xml::ElementStart {token tag attrs args} {
    variable $token
    upvar 0 $token state

    if {![info exists state(parser)]} {
        return -code error \
               -errorinfo [::msgcat::mc "Parser \"%s\" doesn't exist" $token]
    }

    array set namespace [lindex $state(namespace) end]

    set newattrs {}
    foreach {attr val} $attrs {
        set l [::split $attr :]
        set prefix [lindex $l 0]
        set local [lindex $l 1]
        if {[string equal $prefix xmlns]} {
            set namespace($local) $val
        } else {
            lappend newattrs $attr $val
        }
    }

    set l [::split $tag :]
    if {[llength $l] > 1} {
        set prefix [lindex $l 0]
        set tag [lindex $l 1]

        if {![info exists namespace($prefix)]} {
            set xmlns undefined
        } else {
            set xmlns $namespace($prefix)
        } 
    } else {
        set xmlns $namespace()
    }

    set attrs {}
    foreach {attr val} $newattrs {
        set l [::split $attr :]
        if {[llength $l] > 1} {
            set prefix [lindex $l 0]
            set attr [lindex $l 1]

            if {![info exists namespace($prefix)]} {
                if {![string equal $xmlns undefined]} {
                    set attr undefined:$attr
                }
            } elseif {![string equal $xmlns $namespace($prefix)]} {
                set attr $namespace($prefix):$local
            }
        }
        lappend attrs $attr $val
    }

    lappend state(namespace) [array get namespace]

    set state(stack) \
        [linsert $state(stack) 0 [list $tag $xmlns $attrs {} "" ""]]
    if {[llength $state(stack)] == 1} {
        uplevel #0 $state(streamHeaderCmd) [list $attrs]
    }
    return
}

# ::xmpp::xml::ElementEnd --
#
#       A callback procedure which is called by a SAX parser when it finds
#       an XML element end.
#
# Arguments:
#       token               A wrapper token.
#       tag                 A name of the current element.
#
# Results:
#       An empty string.
#
# Side effects:
#       If the current element is a outmost one then stream end command is
#       called. If the current element is level one element then stanza
#       command is called. In both cases the element removed from the stack.
#       Otherwise the current element is inserted into its parent.

proc ::xmpp::xml::ElementEnd {token tag args} {
    variable $token
    upvar 0 $token state

    if {![info exists state(parser)]} {
        return -code error \
               -errorinfo [::msgcat::mc "Parser \"%s\" doesn't exist" $token]
    }

    set state(namespace) [lreplace $state(namespace) end end]

    set newEl [lindex $state(stack) 0]
    set tail [lrange $state(stack) 1 end]

    set len [llength $tail]

    if {$len > 1} {
        set head [lindex $tail 0]
        set els [linsert [lindex $head 3] end $newEl]
        set state(stack) [lreplace $tail 0 0 [lreplace $head 3 3 $els]]
    } elseif {$len == 1} {
        set state(stack) $tail
        uplevel #0 $state(stanzaCmd) [list $newEl]
    } else {
        set state(stack) $tail
        uplevel #0 $state(streamTrailerCmd)
    }
    return
}

# ::xmpp::xml::ElementCdata --
#
#       A callback procedure which is called by a SAX parser when it finds
#       an XML element CData.
#
# Arguments:
#       token               A wrapper token.
#       cdata               Character data.
#
# Results:
#       An empty string.
#
# Side effects:
#       A given CData is added to a current XML element.

proc ::xmpp::xml::ElementCdata {token cdata} {
    variable $token
    upvar 0 $token state

    if {![info exists state(parser)]} {
        return -code error \
               -errorinfo [::msgcat::mc "Parser \"%s\" doesn't exist" $token]
    }

    set newEl [lindex $state(stack) 0]
    set els [lindex $newEl 3]

    if {[llength $els] == 0} {
        set newEl [lreplace $newEl 4 4 [lindex $newEl 4]$cdata]
    } else {
        set els [lindex $newEl 3]
        set lastEl [lindex $els end]
        set lastEl [lreplace $lastEl 5 5 [lindex $lastEl 5]$cdata]
        set els [lreplace $els end end $lastEl]
        set newEl [lreplace $newEl 3 3 $els]
    }

    set state(stack) [lreplace $state(stack) 0 0 $newEl]
    return
}

# vim:ts=8:sw=4:sts=4:et
