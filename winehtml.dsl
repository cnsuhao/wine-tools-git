<!DOCTYPE style-sheet PUBLIC "-//James Clark//DTD DSSSL Style Sheet//EN" [
<!ENTITY walsh-style PUBLIC "-//Norman Walsh//DOCUMENT DocBook HTML Stylesheet//EN" CDATA DSSSL>
<!ENTITY cygnus-style SYSTEM "/usr/lib/sgml/stylesheet/dsssl/docbook/cygnus/cygnus-both.dsl" CDATA DSSSL>
]>

<style-sheet>
<style-specification id="html" use="docbook">
<style-specification-body>

; Use the section id as the filename rather than
; cryptic filenames like x1547.html
(define %use-id-as-filename% #t)

; Repeat the section number in each section to make it easier
; when browsing the doc
(define %section-autolabel% #t)

; Use CSS to make the look of the documentation customizable
(define %stylesheet% "winedoc.css")
(define %stylesheet-type% "text/css")

</style-specification-body>
</style-specification>

<external-specification id="docbook" document="walsh-style">

</style-sheet>
