;;; nice-org-html.el --- Prettier org-to-html export -*- lexical-binding: t; -*-

;; Copyright (C) 2024, Ewan Townshend

;;==============================================================================

;; Author: Ewan Townshend <ewan@etown.dev>
;; URL: https://github.com/ewantown/nice-org-html
;; Package-Version: 1.3
;; Package-Requires: ((emacs "25.1") (s "1.13.0") (dash "2.19.1") (htmlize "1.58") (uuidgen "1.0"))
;; Keywords: org, org-export, html, css, js, tools

;;==============================================================================
;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;==============================================================================
;;; Commentary:

;; This provides an org-to-html publishing pipeline with Emacs theme injection.
;; It enables exporting org files to readable, interactive, responsive html/css.
;; CSS colors are derived from specified light- and dark-mode Emacs themes.
;; Layout is optimized for browser consumption of org files with toc and code.

;; Credits:

;; Shi Tianshu's org-html-themify provided the basic model for css injection.
;; This package has diverged enough to warrant independent distribution.

;; Various stackoverflow posts greatly helped, but alas, they are lost to me.

;;==============================================================================
;; Package provides:
;;
;; nice-org-html-mode
;; nice-org-html-export-to-html
;; nice-org-html-export-to-html-file
;; nice-org-html-publish-to-html
;; nice-org-html-publishing-function

;;==============================================================================
;; TODO:
;;
;; * Make function to "guess" face-attribute values unspecified by theme

;;==============================================================================
;;; Code:

;; Included in emacs >= 25.1
(require 'org)
(require 'ox)
(require 'ox-html)
(require 'ox-publish)

;; Package requires
(require 's)
(require 'dash)
(require 'htmlize)
(require 'uuidgen)

;;==============================================================================
;; User configuration variables

;; Mandatory, with defaults:
(defvar nice-org-html-theme-alist '((light . tsdh-light) (dark . tsdh-dark))
  "Associates light and dark view modes with Emacs themes.")

(defvar nice-org-html-default-mode 'query
  "Default nice HTML page viewing mode.
One of: ((quote light) or (quote dark)) or (quote query).
If (quote query), gets browser-set preference, with fallback to (quote dark).")

(defvar nice-org-html-headline-bullets nil
  "If non-nil, headlines are prefixed with bullets.
If non-nil but not a plist of bullets, e.g. t, default bullets are used.
Else, bullets are strings, b1...b5, specified by plist of form:
'(:h1 b1 :h2 b2 :h3 b3 :h4 b4 :h5 b5).")

;; Optional
(defvar nice-org-html-header nil
    "(Optional) structure to interpret, and/or inject, as page header.

If a string, a path to HTML file containing e.g. a <header> element to inject.

If a list, a list of form:
    '((\"anchor\"' . url0]) (\"link1 . \"url1\") ... (\"linkN\" . \"urlN\")
to be interpreted using default header structure.
If url0 is nil (not a string), then \"anchor\" will not be hyperlinked.")

(defvar nice-org-html-footer nil
  "(Optional) structure to interpret, and/or inject, as page footer.

If a string, a path to HTML file containing e.g. a <footer> element to inject.

If a list, a list of form:
    '((\"anchor\"' . url0]) (\"link1 . \"url1\") ... (\"linkN\" . \"urlN\")
to be interpreted using default footer structure.
If url0 is nil (not a string), then \"anchor\" will not be hyperlinked.")

(defvar nice-org-html-css ""
  "Path to (optional) CSS file to inject.")

(defvar nice-org-html-js ""
  "Path to (optional) JS  file to inject.")

(defvar nice-org-html-options nil
  "Property list mapping additional configuration keywords to values (strings).
Options currently supported:
:layout \"compact\", force header/footer link-collapse into drawer
:layout \"expanded\", prevent header/footer link-collapse into drawer")

(defvar nice-org-html-clr-defs
  '((light . (:note "#0969da" :tip "#1a7f37" :important "#8250df" :warning "#9a6700" :caution "#cf222e"))
    (dark .  (:note "#0969da" :tip "#1a7f37" :important "#8250df" :warning "#9a6700" :caution "#cf222e"))))
;;==============================================================================
;; Package local variables

;; Backups of initial values
(defvar nice-org-html--initial-face-overrides nil)
(defvar nice-org-html--initial-default-style nil)
(defvar nice-org-html--initial-head-extra "")
(defvar nice-org-html--initial-preamble nil)
(defvar nice-org-html--initial-postamble nil)

;; Indicator to avoid overwriting initial values
(defvar nice-org-html--is-active nil)

;; Temp var to avoid needless reloading of themes
(defvar nice-org-html--temp-theme nil)

(defun nice-org-html--local-path (filename)
  "Get expanded path FILENAME in this directory."
  (let ((dir (file-name-directory (or load-file-name (buffer-file-name)))))
    (expand-file-name filename dir)))

(defvar nice-org-html--base-css (nice-org-html--local-path "nice-org-html.css")
  "Path to included CSS template that styles package-generated HTML.")
(defvar nice-org-html--base-js  (nice-org-html--local-path "nice-org-html.js")
  "Path to included JS file that governs package-generated HTML.")

;;==============================================================================
;; Setup and Teardown

(defun nice-org-html--setup ()
  "Set up nice-org-html mode."
  (unless nice-org-html--is-active
    (add-hook 'org-export-before-processing-functions #'nice-org-html--inject)
    (setq nice-org-html--is-active t
	  org-html-head-include-default-style nil
	  nice-org-html--initial-face-overrides htmlize-face-overrides
	  nice-org-html--initial-head-extra org-html-head-extra
	  nice-org-html--initial-preamble   'org-html-preamble
	  nice-org-html--initial-postamble  'org-html-postamble
	  htmlize-face-overrides
	  (append
	   nice-org-html--initial-face-overrides
	   '(font-lock-keyword-face
	     (:foreground "var(--clr-keyword)"
			  :background "var(--bg-keyword)")
	     font-lock-constant-face
	     (:foreground "var(--clr-constant)"
			  :background "var(--bg-constant)")
	     font-lock-comment-face
	     (:foreground "var(--clr-comment)"
			  :background "var(--bg-comment)")
	     font-lock-comment-delimiter-face
	     (:foreground "var(--clr-comment-delimiter)"
			  :background "var(--bg-comment-delimiter)")
	     font-lock-function-name-face
	     (:foreground "var(--function-clr-name)"
			  :background "var(--function-bg-name)")
	     font-lock-variable-name-face
	     (:foreground "var(--clr-variable)"
			  :background "var(--bg-variable)")
	     font-lock-preprocessor-face
	     (:foreground "var(--clr-preprocessor)"
			  :background "var(--bg-preprocessor)")
	     font-lock-doc-face
	     (:foreground "var(--clr-doc)"
			  :background "var(--bg-doc)")
	     font-lock-builtin-face
	     (:foreground "var(--clr-builtin)"
			  :background "var(--bg-builtin)")
	     font-lock-string-face
	     (:foreground "var(--clr-string)"
			  :background "var(--bg-string)"))))))

(defun nice-org-html--teardown ()
  "Tear down nice-org-html mode."
  (when nice-org-html--is-active
    (remove-hook 'org-export-before-processing-functions #'nice-org-html--inject)
    (setq nice-org-html--is-active nil
	  org-html-head-include-default-style nice-org-html--initial-default-style
	  htmlize-face-overrides nice-org-html--initial-face-overrides
	  org-html-head-extra nice-org-html--initial-head-extra
	  org-html-preamble   nice-org-html--initial-preamble
	  org-html-postamble  nice-org-html--initial-postamble)))

;;==============================================================================
;; HTML Modifications

(defun nice-org-html--inject (export-backend)
  "Inject custom styling and scripts when EXPORT-BACKEND is `nice-html'."
  (when (eq export-backend 'nice-html)
    (let ((style (nice-org-html--style))
	  (preamble (nice-org-html--preamble))
	  (postamble (nice-org-html--postamble)))
      (setq org-html-head-extra (concat style nice-org-html--initial-head-extra))
      (setq org-html-preamble   preamble)
      (setq org-html-postamble  postamble))))

(defun nice-org-html--style ()
  "Construct html <style> element for header."
  (concat
   "<style type='text/css'>\n"
   "<!--/*--><![CDATA[/*><!--*/\n"
   (with-temp-buffer
     (insert-file-contents nice-org-html--base-css)
     (goto-char (point-max))
     (when-let* ((css (nice-org-html--bullet-css))) (insert css))
     (goto-char (point-max))
     (when (and nice-org-html-css
		(not (equal "" nice-org-html-css))
		(file-exists-p nice-org-html-css))
       (insert-file-contents nice-org-html-css))
     (nice-org-html--interpolate-css)
     (buffer-string))
   "/*]]>*/-->\n"
   "</style>\n"))

(defun nice-org-html--bullet-css ()
  "CSS string if `nice-org-html-headline-bullets' is non-nil, else nil."
  (and-let* ((bulletvar nice-org-html-headline-bullets)
	     (bullets
	      (if (and (listp bulletvar)
		       (--all?
			(and (plist-member bulletvar it)
			     (stringp (plist-get bulletvar it)))
			'(:h1 :h2 :h3 :h4 :h5)))
		  bulletvar
		'(:h1 "◉" :h2 "✸" :h3 "▷" :h4 "⦁" :h5 "○")))
	     (mkcss
	      (lambda (n)
		(let* ((bullet (plist-get bullets (intern (format ":h%d" n)))))
		  (format (concat "h%d::before { content: '%s';\n"
				  "margin-right: calc(%d * 0.2%dem);\n}\n")
			  (+ 1 n) ;; HTML h1 reserved for title
			  bullet
			  (if (equal bullet "") 0 (+ 1 n))
			  (+ 1 n))))))
    (--reduce-from (concat it acc) ""
		     (--map (funcall mkcss it) '(1 2 3 4 5)))))

(defun nice-org-html--preamble ()
  "Construct html preamble to main content area."
  (concat (or (nice-org-html--header-html) "")
	  "<div id='view-controls'>"
	  "<div id='toggle-mode' title='Mode'>&#9788;</div>"
	  "<div id='goto-top' title='Top'>&#8963;</div>"
	  "<div id='toggle-toc' title='Contents'>&#9776;</div>"
	  "</div>"))

(defun nice-org-html--bar-builder (data class)
  "Constructs components of header/footer bar, returns as pair."
  (and-let* ((_ (consp data))
	     (_ (--all? (and (consp it) (stringp (car it))) data))
	     (tcell (car data))
	     (thref (or (cdr tcell) 'f))
	     (mklink
	      (lambda (c) (concat "<li class='nav-item'>\n"
			     "<a class='nav-link' href='" (cdr c) "'>\n"
			     (car c)
			     "</a>\n</li>")))
	     (left-html
	      (let* ((tag (concat (or (and (not (eq thref 'f)) "a") "span"))))
		(concat "<" tag " class='" class "'"
			(or (and (equal tag "a")
				 (format "href='%s' " thref))
			    "")
			">\n" (car tcell) "\n</" tag ">\n"))))
    `(,left-html . ,(--reduce-from (concat acc it "\n") ""
				   (--map (funcall  mklink it) (cdr data))))))

(defun nice-org-html--header-html ()
  "Constructs HTML string if `nice-org-html-header' is header data, else nil"
  (and-let* ((data nice-org-html-header))
    (or (and (stringp data) (not (equal "" data)) (file-exists-p data)
	     (concat "<div id='injected-header' class='injected'>"
		     (with-temp-buffer (insert-file-contents data)
				       (buffer-string))
		     "</div>"))

	(and-let* ((components (nice-org-html--bar-builder data "nav-title"))
		   (left-html (car components))
		   (links-html (cdr components)))
	  (concat "<div id='generated-header' class='generated'>"
		  "<header>\n <nav>\n"
		  left-html
		  "<input id='nav-toggle-top' class='nav-toggle' type='checkbox'>\n"
		  "<label class='nav-button' for='nav-toggle-top'><span/></label>\n"
		  "<div class='separator menu-sep'></div>\n"
		  "<ul class='nav-list'>\n"
		  links-html
		  "</ul>\n" "<div class='separator'></div>\n" "</nav>\n"
		  "</header>\n</div>\n")))))


(defun nice-org-html--footer-html ()
  "Constructs HTML string if `nice-org-html-footer' is footer data, else nil"
  (and-let* ((data nice-org-html-footer))
    (or (and (stringp data) (not (equal "" data)) (file-exists-p data)
	     (concat "<div id='injected-footer' class='injected'>"
		     (with-temp-buffer (insert-file-contents data)
				       (buffer-string))
		     "</div>"))
	(and-let* ((components (nice-org-html--bar-builder data "nav-author"))
		   (left-html (car components))
		   (links-html (cdr components)))
	  (concat "<div id='generated-footer' class='generated'>"
		  "<footer>\n <nav>\n"
		  "<div class='separator'></div>\n"
		  left-html
		  "<input id='nav-toggle-bot' class='nav-toggle' type='checkbox'>\n"
		  "<label class='nav-button' for='nav-toggle-bot'><span/></label>\n"
		  "<div class='separator menu-sep'></div>\n"
		  "<ul class='nav-list'>\n"
		  links-html
		  "</ul>\n" "</nav>\n"
		  "</footer>\n</div>\n")))))


(defun nice-org-html--postamble ()
  "Construct html postamble to main content area."
  (concat
   (or (nice-org-html--footer-html) "")
   "<script type=\"text/javascript\">\n"
   "<!--/*--><![CDATA[/*><!--*/\n"
   "if (!document.cookie.split('; ').find(r => r.startsWith('mode'))) {\n"
   "document.cookie = 'mode=" (symbol-name nice-org-html-default-mode) "'\n}\n"
   "document.cookie = 'light="
   (symbol-name (cdr (assoc 'light nice-org-html-theme-alist))) "'\n"
   "document.cookie = 'dark="
   (symbol-name (cdr (assoc 'dark  nice-org-html-theme-alist))) "'\n"
   (if (and nice-org-html-options (plistp nice-org-html-options))
       (concat "document.cookie = 'options="
	       (string-remove-suffix
		"__"
		(--reduce-from
		 (concat acc (string-remove-prefix ":" (symbol-name (car it)))
			 ":" (cdr it) "__")
		 ""
		 (--filter it
			   (--map
			    (if (plist-member nice-org-html-options it)
				(let ((ent (plist-get nice-org-html-options it)))
				  (cons it (cond ((stringp ent) ent)
						 (ent "t")
						 (t "nil"))))
			      nil)
			    nice-org-html-options))))
	       "';\n")
     "")
   (with-temp-buffer
     (insert-file-contents nice-org-html--base-js)
     (when (and nice-org-html-js
		(not (equal "" nice-org-html-js))
		(file-exists-p nice-org-html-js))
       (insert-file-contents nice-org-html-js))
     (buffer-string))
   "/*]]>*/-->\n"
   "</script>"
   "<div hidden>"
   "Generated by: https://github.com/ewantown/nice-org-html"
   "</div>"))

;;==============================================================================
;; Emacs theme / CSS Interpolation

(defun nice-org-html--interpolate-css ()
  "Interpolate hex values in CSS template."
  (setq inhibit-redisplay t)
  (let ((initial-themes custom-enabled-themes))
    (mapc (lambda (th) (disable-theme th)) initial-themes)
    (goto-char (point-min))
    ;; loop over CSS template variables
    (while (re-search-forward "#{.+?}" nil t)
      (-let* ((beg (match-beginning 0))
	      (end (match-end 0))
	      (str (buffer-substring-no-properties beg end))
	      (val (nice-org-html--get-hex-val str)))
	(delete-region beg end)
	(insert val)))
    (goto-char (point-max))
    ;; restore prior theme configuration
    (unless (-contains? initial-themes nice-org-html--temp-theme)
      (disable-theme nice-org-html--temp-theme))
    (setq nice-org-html--temp-theme nil)
    (setq custom-enabled-themes initial-themes)
    (mapc (lambda (th) (load-theme th t nil)) initial-themes))
  (setq inhibit-redisplay nil))

(defun nice-org-html--get-hex-val (str)
  "Interpret STR of form #{mode:entity:attribute:key?|...} against themes."
  (let* ((clauses (split-string (substring str 2 -1) "|"))
	 (val (car (-keep 'nice-org-html--interp-clause clauses))))
    (if (null val) "initial" (nice-org-html--color-to-hex val 2))))

(defun nice-org-html--interp-clause (c)
  "Interpret clause C against themes."
  (-let* (((m  e  a  k)  (s-split ":" c))
	  ((ms es as ks) `(,(intern m)
			   ,(intern e)
			   ,(intern (concat ":" a))
			   ,(and k (intern (concat ":" k)))))
	  (theme (alist-get ms nice-org-html-theme-alist)))
    (if (eq es 'user-defined)
	(plist-get (alist-get ms nice-org-html-clr-defs) as)            
      (progn
	;; load theme associated with mode of the clause
	(unless (equal theme nice-org-html--temp-theme)
	  (disable-theme nice-org-html--temp-theme)
	  (load-theme theme t nil)
	  (setq nice-org-html--temp-theme theme))
	;; grab value for face-attribute specified by clause
	(let ((val (face-attribute es as)))
	  (unless (or (not val) (equal val 'unspecified))
	    (if ks (plist-get val ks) val)))))))

;;==============================================================================
;; Custom export backend for better org doc content export

(defun nice-org-html--src-block (src-block contents info)
  "Transform SRC-BLOCK with CONTENTS and INFO to html with copy button."
    (let* ((btn-id (concat "btn_" (s-replace "-" "" (uuidgen-4))))
	   (lang (org-element-property :language src-block))
	   (content
	    (let ((print-escape-newlines t))
	      (prin1-to-string (org-export-format-code-default src-block info))))
	   (content^
	    (s-chop-prefix "\""
			   (s-chop-suffix "\""
					  (s-replace "`" "\\`" content)))))
      (concat "<div class='org-src-wrapper'>\n"
	      "<div class='org-src-bar'>"
	      (nice-org-html--src-lang-label lang)
	      (nice-org-html--copy-src-button btn-id)
	      (nice-org-html--copy-src-script btn-id content^)
	      "</div>"
	      (org-export-with-backend 'html src-block contents info)
	      "</div>")))

(defun nice-org-html--src-lang-label (lang)
  "Construct language label for LANG"
  (concat "<span class='srcLangLabel'>" (upcase lang) "</span>"))


(defun nice-org-html--copy-src-button (btn-id)
  "Construct html <button> for unique BTN-ID."
  (concat "<button class='copyBtn' name=" btn-id ">&#10697;</button>"))

(defun nice-org-html--copy-src-script (btn-id txt)
  "Construct html <script> for copy button with BTN-ID and source content TXT."
  (concat "\n<script type='text/javascript'>\n"
	  "var copyBtn" btn-id "=document.querySelector('button[name=" btn-id "]');\n"
	  "copyBtn" btn-id ".addEventListener('click', function(event) {\n"
	  "let res = copyTextToClipboard(`" txt "`);"
	  "copyBtn" btn-id ".innerHTML = res ? '&#10003;' : 'error';"
	  "setTimeout(() => { copyBtn" btn-id ".innerHTML = '&#10697;'}, 3000);"
	  "\n});\n</script>\n"))

(defun nice-org-html--admonition (block contents info)
  (let ((type (org-element-property :type block)))
    (concat "<div class='admonition " type "'>"
	    "<div class='admonition-title " type "'>"
	    (upcase (substring type 0 1)) (downcase (substring type 1))
	    "</div>"
	    "<div class='admonition-content " type "'>"
	    contents
	    "</div>"
	    "</div>")))

(defun nice-org-html--special-block (block contents info)
  "Transform SPECIAL-BLOCK with CONTENTS and INFO to html"
  (let ((block-type (org-element-property :type block)))
    (cond ((member block-type '("note" "tip" "important" "warning" "caution"))
	   (nice-org-html--admonition block contents info))
	  (t (org-html-special-block block contents info)))))

(org-export-define-derived-backend 'nice-html 'html
  :translate-alist
  '((src-block . nice-org-html--src-block)
    (special-block . nice-org-html--special-block))
  :menu-entry
  '(?H "Export to nice HTML"
       ((?h "As HTML file" nice-org-html-export-to-html)
	(?H "As specified file" nice-org-html-export-to-html-file)
	(?o "As HTML file and open"
	    (lambda (a s v b)
	      (if a (nice-org-html-export-to-html t s v b)
		(org-open-file (nice-org-html-export-to-html nil s v b))))))))

;;==============================================================================
;; These functions extend the (similarly named) ox-html ones to the new backend

;;;###autoload
(defun nice-org-html-export-to-html
    (&optional async subtreep visible-only body-only ext-plist)
  "Export current buffer to HTML file in PWD using nice-org-html custom backend.
See docs for `org-html-export-to-html', which this function emulates."
  (interactive)
  (let* ((convert (lambda (s) (and (not (equal "" s))
			      (let ((val (read s)))
				(if (listp val) val (symbol-name val))))))
	 (present (lambda (x) (if (stringp x) x (prin1-to-string x))))
	 (nice-org-html-header
	  (funcall convert (read-string "Header file or list (optional): "
				  (funcall present nice-org-html-header) nil nil nil)))
	 (nice-org-html-footer
	  (funcall convert (read-string "Footer file or list (optional): "
				  (funcall present nice-org-html-footer) nil nil nil)))
	 (nice-org-html-css
	  (read-string "Additional CSS file (optional): "
		       nice-org-html-css nil nil nil))
	 (nice-org-html-js
	  (read-string "Additional JS file (optional): "
		       nice-org-html-js nil nil nil))
	 (nice-org-html-options
	  (funcall convert (read-string "Options plist (optional): "
			      (funcall present nice-org-html-options) nil nil nil)))
	 (extension (concat
		     (when (> (length org-html-extension) 0) ".")
		     (or (plist-get ext-plist :html-extension)
			 org-html-extension
			 "html")))
	 (file (org-export-output-file-name extension subtreep))
	 (org-export-coding-system org-html-coding-system))
    (org-export-to-file 'nice-html file
      async subtreep visible-only body-only ext-plist)))

;;;###autoload
(defun nice-org-html-export-to-html-file
    (&optional async subtreep visible-only body-only ext-plist)
  "Export current buffer as nice HTML to interactively specified file.
Optional arguments are pass-through, so see docs for `org-export-to-file'."
  (let* ((convert (lambda (s) (and (not (equal "" s))
			      (let ((val (read s)))
				(if (listp val) val (symbol-name val))))))
	 (present (lambda (x) (if (stringp x) x (prin1-to-string x))))
	 (file
	  (read-string "Target file path (mandatory): "))
	 (nice-org-html-header
	  (funcall convert (read-string "Header file or list (optional): "
				  (funcall present nice-org-html-header) nil nil nil)))
	 (nice-org-html-footer
	  (funcall convert (read-string "Footer file or list (optional): "
				  (funcall present nice-org-html-footer) nil nil nil)))
	 (nice-org-html-css
	  (read-string "Additional CSS file (optional): "
		       nice-org-html-css nil nil nil))
	 (nice-org-html-js
	  (read-string "Additional JS file (optional): "
		       nice-org-html-js nil nil nil))
	 (nice-org-html-options
	  (funcall convert (read-string "Options plist (optional): "
			      (funcall present nice-org-html-options) nil nil nil))))
    (org-export-to-file 'nice-html file
      async subtreep visible-only body-only ext-plist nil)))

;;;###autoload
(defun nice-org-html-publish-to-html (plist filename pub-dir)
  "Publish an org file to HTML using nice-org-html custom export backend.
See docs for `org-html-publish-to-html', which this function emulates."
  (org-publish-org-to 'nice-html filename
		      (concat (when (> (length org-html-extension) 0) ".")
			      (or (plist-get plist :html-extension)
				  org-html-extension
				  "html"))
		      plist pub-dir))

;;;###autoload
(defmacro nice-org-html-publishing-function (&rest config)
  "Create org-publishing function which quasi-closes over passed configuration.

CONFIG is a plist, supporting the following properties:
:theme-alist, shadows `nice-org-html-theme-alist'.
:default-mode, shadows `nice-org-html-theme-alist'.
:headline-bullets, shadows `nice-org-html-headline-bullets'
:header, shadows `nice-org-html-header'.
:footer, shadows `nice-org-html-footer'.
:css, shadows `nice-org-html-css'.
:js, shadows `nice-org-html-js'.
:layout, nil (for dynamic) or one of {\"compact\" \"expanded\"}.
:clr-defs, shadows `nice-org-html-clr-defs'.

Required but unspecified parameters are backstopped by globally set values."
  (declare (debug t))
  (let* ((sym (gensym "nice-org-html-publishing-function-")))
    `(defun ,sym (plist filename pub-dir)
       (let* ((config ',config)
	      (backstop
	       (lambda (key stop &optional pred)
		 (let* ((mem (plist-member config key))
			(ent (plist-get config key)))
		   (cond ((and mem pred) (if (funcall pred ent) ent stop))
			 (mem ent)
			 (t stop)))))
	      (nice-org-html-theme-alist
	       (funcall backstop :theme-alist nice-org-html-theme-alist
		 (lambda (e)
		   (or (and (consp e) (assoc 'light e) (assoc 'dark e)
			    (--all? (member it (custom-available-themes))
				    (--map (cdr it) e)))
		       (progn (when e (message "Error: invalid themes: %S" e))
			      nil)))))
	      (nice-org-html-default-mode
	       (funcall backstop :default-mode nice-org-html-default-mode
		 (lambda (e)
		   (or (and (symbolp e) (member e '(light dark)))
		       (progn (when e (message "Error: invalid mode: %S" e))
			      nil)))))
	      (nice-org-html-headline-bullets
	       (funcall backstop :headline-bullets nice-org-html-headline-bullets))
	      (nice-org-html-header
	       (funcall backstop :header nice-org-html-header
		 (lambda (e)
		   (or (and (stringp e) (file-exists-p e))
		       (and (consp e)
			    (--all? (and (consp it) (stringp (car it))) e))
		       (progn (when e (message "Error: invalid header: %S" e))
			      nil)))))
	      (nice-org-html-footer
	       (funcall backstop :footer nice-org-html-footer
		 (lambda (e)
		   (or (and e (stringp e) (file-exists-p e))
		       (and (consp e)
			    (--all? (and (consp it) (stringp (car it))) e))
		       (progn (when e (message "Error: invalid footer: %S" e))
			      nil)))))
	      (nice-org-html-css
	       (funcall backstop :css nice-org-html-css
		 (lambda (e)
		   (or (and e (stringp e) (file-exists-p e))
		       (progn (when e (message "Error: invalid CSS file: %S" e))
			  nil)))))
	      (nice-org-html-js
	       (funcall backstop :js nice-org-html-js
		 (lambda (e)
		   (or (and (stringp e) (file-exists-p e))
		       (progn (when e (message "Error: invalid JS file: %S" e))
			      nil)))))
	      (nice-org-html-clr-defs
	       (let* ((clr-props '(:note :tip :important :warning :caution))
		      (init (copy-sequence nice-org-html-clr-defs))	     
		      (defs  (funcall backstop :clr-defs init))
		      (light (or (alist-get 'light defs) (alist-get 'light init)))
		      (dark  (or (alist-get 'dark  defs) (alist-get 'dark  init)))
		      (merge
		       (lambda (sup sub)
			 (--reduce-from
			  (if (plist-member sub it)
			      acc
			      (plist-put acc it (plist-get sup it))
			    acc)
			  sub
			  clr-props))))
		 `((light . ,(funcall merge (alist-get 'light init) light))
		   (dark  . ,(funcall merge (alist-get 'dark  init) dark)))))
	      (base '(:theme-alist :default-mode))
	      (main (append base '(:headline-bullets :header :footer :css :js :clr-defs)))
	      (options nice-org-html-options)
	      (nice-org-html-options
	       (--reduce-from
		(plist-put acc it (plist-get config it))
		options
		(-filter (lambda (s) (and s (--all? (not (eq s it)) main)))
			 (--map (car-safe (plist-member config it)) config)))))
	 (nice-org-html-publish-to-html plist filename pub-dir)))))


(make-obsolete 'nice-org-html-make-publishing-function
	       'nice-org-html-publishing-function
	       "1.3")
;;;###autoload
(defmacro nice-org-html-make-publishing-function
    (theme-alist default-mode bullets header footer css js &optional options)
  "DEPRECATED. Use `nice-org-html-publishing-function' macro instead.

THEME-ALIST shadows `nice-org-html-theme-alist'.
DEFAULT-MODE shadows `nice-org-html-default-mode'.
HEADER shadows `nice-org-html-header'.
FOOTER shadows `nice-org-html-footer'.
CSS shadows `nice-org-html-css'.
JS shadows `nice-org-html-js'.
OPTIONS shadows `nice-org-html-options'."      
  (let ((sym (gensym "nice-org-html-publishing-function-")))
    `(defun ,sym (plist filename pub-dir)
       (let* ((nice-org-html-theme-alist  ,theme-alist)
	      (nice-org-html-default-mode ,default-mode)
	      (nice-org-html-headline-bullets ,bullets)
	      (nice-org-html-header ,header)
	      (nice-org-html-footer ,footer)
	      (nice-org-html-css ,css)
	      (nice-org-html-js  ,js)
	      (nice-org-html-options
	       (--reduce-from
		(plist-put acc it (plist-get ,options it))
		nice-org-html-options
		(-filter
		 (lambda (s) s)
		 (--map (car-safe (plist-member ,options it)) ,options)))))
	 (nice-org-html-publish-to-html plist filename pub-dir)))))

;;==============================================================================
;; Defined mode

;;;###autoload
(define-minor-mode nice-org-html-mode
  "Mode for prettier .org to .html exporting."
  :version 1.0
  (if nice-org-html-mode (nice-org-html--setup) (nice-org-html--teardown)))

;;==============================================================================
(defvar nice-org-html-embed-images nil
  "If non-nil, embed base-64-encoded images in exported html.")

(defun nice-org-html--base-64-encode-file (file)
  "Base 64 encode contents of file."
  (base64-encode-string
   (with-temp-buffer
     (insert-file-contents
      (url-unhex-string
       (url-filename
	(url-generic-parse-url file))))
     (buffer-string))))

(defun nice-org-html--format-image (src atts info)
  "Override for `org-html--format-image' that embeds base64-encoded image."
  (org-html-close-tag
   "img"
   (org-html--make-attribute-string
    (org-combine-plists
     (list :src (format "data:image/png;base64,%s"
			(nice-org-html--base-64-encode-file src))
	   :alt (if (string-match-p
		     (concat "^" org-preview-latex-image-directory) src)
		    (org-html-encode-plain-text
		     (org-find-text-property-in-string 'org-latex-src src))
		  (file-name-nondirectory src)))
     (if (string= "svg" (file-name-extension src))
	 (org-combine-plists '(:class "org-svg") atts '(:fallback nil))
       atts)))
   info))

(defun nice-org-html--format-image-wrapper (format-fn &rest args)
  "Wrap formatting function to provide embedded images option."
  (if nice-org-html-embed-images
      (apply #'nice-org-html--format-image args)
    (apply format-fn args)))

(advice-add 'org-html--format-image
	    :around
	    #'nice-org-html--format-image-wrapper)

;;==============================================================================
;; These helper functions are derived from Drew Adams' hexrgb.el
;; https://www.emacswiki.org/emacs/download/hexrgb.el

(defun nice-org-html--rgb-hex-string-p (color)
  "Non-nil if COLOR is an RGB string #XXXXXXXXXXXX.
Each X is a hex digit.  The number of Xs must be a multiple of 3, with
the same number of Xs for each of red, green, and blue."
  (string-match "^#\\([a-fA-F0-9][a-fA-F0-9][a-fA-F0-9]\\)+$" color))

(defun nice-org-html--color-to-hex (color &optional nb-digits)
  "Return the RGB hex string, starting with \"#\", for the COLOR.
NB-DIGITS is number of hex digits per component, in (1 2 3 4), default 4.
The output string is `#' followed by NB-DIGITS hex digits for each
color component.  So for default NB-DIGITS, the form is \"#RRRRGGGGBBBB\"."
  (cond ((nice-org-html--rgb-hex-string-p color) color)
	((not (x-color-values color)) (error "No such color: %S" color))
	(t (let ((digits (or nb-digits 4))
		 (components (x-color-values color))
		 (int-to-hex
		  (lambda (int nbd)
		    (substring
		     (format (concat "%0" (number-to-string nbd) "X") int)
		     (- nbd)))))
	     (concat "#"
		     (funcall int-to-hex (nth 0 components) digits)      ; red
		     (funcall int-to-hex (nth 1 components) digits)      ; green
		     (funcall int-to-hex (nth 2 components) digits)))))) ; blue

;;==============================================================================
(provide 'nice-org-html)

;;; nice-org-html.el ends here
