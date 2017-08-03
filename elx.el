;;; elx.el --- extract information from Emacs Lisp libraries

;; Copyright (C) 2008-2017  Jonas Bernoulli

;; Author: Jonas Bernoulli <jonas@bernoul.li>
;; Created: 20081202
;; Package-Requires: ((emacs "24.4"))
;; Homepage: https://github.com/emacscollective/elx
;; Keywords: docs, libraries, packages

;; This file is not part of GNU Emacs.

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This package extracts information from Emacs Lisp libraries.  It
;; extends built-in `lisp-mnt', which is only suitable for libraries
;; that closely follow the header conventions.  Unfortunately there
;; are many libraries that do not - this library tries to cope with
;; that.

;; It also defines some new extractors not available in `lisp-mnt',
;; and some generalizations of extractors available in the latter.

;;; Code:

(require 'lisp-mnt)

(defgroup elx nil
  "Extract information from Emacs Lisp libraries."
  :group 'maint
  :link '(url-link :tag "Homepage" "https://github.com/tarsius/elx"))

;; Redefine to undo bug introduced in Emacs
;; bf3f6a961f378f35a292c41c0bfbdae88ee1b1b9
;; https://debbugs.gnu.org/cgi/bugreport.cgi?bug=22510
(defun lm-header (header)
  "Return the contents of the header named HEADER."
  ;; This breaks `lm-header-multiline': (save-excursion
  (goto-char (point-min))
  (let ((case-fold-search t))
    (when (and (re-search-forward (lm-get-header-re header) (lm-code-mark) t)
               ;;   RCS ident likes format "$identifier: data$"
               (looking-at
                (if (save-excursion
                      (skip-chars-backward "^$" (match-beginning 0))
                      (= (point) (match-beginning 0)))
                    "[^\n]+" "[^$\n]+")))
      (match-string-no-properties 0))))

;;; Extract Summary

(defun elx-summary (&optional file sanitize)
  "Return the one-line summary of file FILE.
If optional FILE is nil return the summary of the current buffer
instead.  When optional SANITIZE is non-nil a trailing period is
removed and the first word is upcases."
  (lm-with-file file
    (let ((summary-match
           (lambda ()
             (and (looking-at lm-header-prefix)
                  (progn (goto-char (match-end 0))
                         ;; There should be three dashes after the
                         ;; filename but often there are only two or
                         ;; even just one.
                         (looking-at "[^ ]+[ \t]+-+[ \t]+\\(.*\\)"))))))
      (if (or (funcall summary-match)
              ;; Some people put the -*- specification on a separate
              ;; line, pushing the summary to the second or third line.
              (progn (forward-line) (funcall summary-match))
              (progn (forward-line) (funcall summary-match)))
          (let ((summary (match-string-no-properties 1)))
            (unless (equal summary "")
              ;; Strip off -*- specifications.
              (when (string-match "[ \t]*-\\*-.*-\\*-" summary)
                (setq summary (substring summary 0 (match-beginning 0))))
              (when sanitize
                (when (string-match "\\.$" summary)
                  (setq summary (substring summary 0 -1)))
                (when (string-match "^[a-z]" summary)
                  (setq summary
                        (concat (upcase (substring summary 0 1))
                                (substring summary 1)))))
              (unless (equal summary "")
                summary)))))))

;;; Extract Keywords

(defcustom elx-remap-keywords nil
  "List of keywords that should be replaced or dropped by `elx-keywords'.
If function `elx-keywords' is called with a non-nil SANITIZE
argument it checks this variable to determine if keywords should
be dropped from the return value or replaced by another.  If the
cdr of an entry is nil then the keyword is dropped; otherwise it
will be replaced with the keyword in the cadr."
  :group 'elx
  :type '(repeat (list string (choice (const  :tag "drop" nil)
                                      (string :tag "replacement")))))

(defvar elx-keywords-regexp "^[- a-z]+$")

(defun elx-keywords-list (&optional file sanitize symbols)
  "Return list of keywords given in file FILE.
If optional FILE is nil return keywords given in the current
buffer instead.  If optional SANITIZE is non-nil replace or
remove some keywords according to option `elx-remap-keywords'.
If optional SYMBOLS is non-nil return keywords as symbols,
else as strings."
  (lm-with-file file
    (let (keywords)
      (dolist (line (lm-header-multiline "keywords"))
        (dolist (keyword (split-string
                          (downcase line)
                          (concat "\\("
                                  (if (string-match-p "," line)
                                      ",[ \t]*"
                                    "[ \t]+")
                                  "\\|[ \t]+and[ \t]+\\)")
                          t))
          (when sanitize
            (let ((remap (assoc keyword elx-remap-keywords)))
              (and remap (setq keyword (cadr remap))))
            (and keyword
                 (string-match elx-keywords-regexp keyword)
                 (add-to-list 'keywords keyword)))))
      (setq keywords (sort keywords 'string<))
      (if symbols (mapcar #'intern keywords) keywords))))

;;; Extract Commentary

(defun elx-commentary (&optional file sanitize)
  "Return the commentary in file FILE, or current buffer if FILE is nil.
Return the value as a string.  In the file, the commentary
section starts with the tag `Commentary' or `Documentation' and
ends just before the next section.  If the commentary section is
absent, return nil.

If optional SANITIZE is non-nil cleanup the returned string.
Leading and trailing whitespace is removed from the returned
value but it always ends with exactly one newline.  On each line
the leading semicolons and exactly one space are removed,
likewise leading \"\(\" is replaced with just \"(\".  Lines
consisting only of whitespace are converted to empty lines."
  (lm-with-file file
    (let ((start (lm-section-start lm-commentary-header t)))
      (when start
        (goto-char start)
        (let ((commentary (buffer-substring-no-properties
                           start (lm-commentary-end))))
          (when sanitize
            (mapc (lambda (elt)
                    (setq commentary (replace-regexp-in-string
                                      (car elt) (cdr elt) commentary)))
                  '(("^;+ ?"        . "")
                    ("^\\\\("       . "(")
                    ("^\n"        . "")
                    ("^[\n\t\s]\n$" . "\n")
                    ("\\`[\n\t\s]*" . "")
                    ("[\n\t\s]*\\'" . "")))
            (setq commentary
                  (when (string-match "[^\s\t\n]" commentary)
                    (concat commentary "\n"))))
          commentary)))))

;;; Extract Pages

(defun elx-wikipage (&optional file)
  "Extract the Emacswiki page of the specified package."
  (let ((page (lm-with-file file
                (lm-header "Doc URL"))))
    (and page
         (string-match
          "^<?http://\\(?:www\\.\\)?emacswiki\\.org.*?\\([^/]+\\)>?$"
          page)
         (match-string 1 page))))

;;; Extract License

(defconst elx-gnu-permission-statement-regexp
  ;; The stray "n?" is for https://github.com/myuhe/...
  (replace-regexp-in-string
   "\s" "[\s\t\n;]+"
   ;; is free software[.,:;]? \
   ;; you can redistribute it and/or modify it under the terms of the \
   "\
GNU \\(?1:Lesser \\| Library \\|Affero \\|Free \\)?\
General Public Licen[sc]e[.,:;]? \
\\(?:as published byn? the \\(?:Free Software Foundation\\|FSF\\)[.,:;]? \\)?\
\\(?:either \\)?\
\\(?:GPL \\)?\
version \\(?2:[0-9.]*[0-9]\\)[.,:;]?\
\\(?: of the Licen[sc]e[.,:;]?\\)?\
\\(?3: or \\(?:(at your option) \\)?any later version\\)?"))

(defconst elx-bsd-permission-statement-regexp
  (replace-regexp-in-string
   "%" "[-0-4).*\s\t\n;]+"
   (replace-regexp-in-string
    "\s" "[\s\t\n;]+"
    ;; Copyright (c) <year>, <copyright holder>
    ;; All rights reserved.
    "\
Redistribution and use in source and binary forms, with or without \
modification, are permitted provided that the following conditions are met: \
%Redistributions of source code must retain the above copyright \
notice, this list of conditions and the following disclaimer\\.
\
%Redistributions in binary form must reproduce the above copyright \
notice, this list of conditions and the following disclaimer in the \
documentation and/or other materials provided with the distribution\\. \
\
\\(?3:\\(?4:%All advertising materials mentioning features or use of this software \
must display the following acknowledgement: \
\
This product includes software developed by .+?\\. \\)?\
%Neither the name of .+? nor the \
names of its contributors may be used to endorse or promote products \
derived from this software without specific prior written permission\\. \\)?\
\
THIS SOFTWARE IS PROVIDED BY \
\\(?:THE COPYRIGHT \\(HOLDER\\|OWNER\\)S?\\(?: \\(?:AND\\|OR\\) CONTRIBUTORS\\)?\\|.+?\\) \
[\"'`]*AS IS[\"'`]* AND ANY \
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED \
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE \
DISCLAIMED. IN NO EVENT SHALL \
\\(?:THE COPYRIGHT \\(HOLDER\\|OWNER\\)S?\\(?: \\(?:AND\\|OR\\) CONTRIBUTORS\\)?\\|.+?\\) \
BE LIABLE FOR ANY \
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES \
\(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; \
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND \
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT \
\(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS \
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE\\.")))

(defconst elx-mit-permission-statement-regexp
  (replace-regexp-in-string
   "\s" "[\s\t\n;]+"
   ;; Copyright (c) <year> <copyright holders>
   ;;
   "\
Permission is hereby granted, free of charge, to any person obtaining a copy \
of this software and associated documentation files\\(?: (the \"Software\")\\)?, \
to deal \
in the Software without restriction, including without limitation the rights \
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell \
copies of the Software, and to permit persons to whom the Software is \
furnished to do so, subject to the following conditions: \
\
The above copyright notice and this permission notice shall be included in all \
copies or substantial portions of the Software\\. \
\
THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR \
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, \
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT\\. IN NO EVENT SHALL THE \
\\(?:AUTHORS OR COPYRIGHT HOLDERS\\|.+?\\) \
BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER \
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, \
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE \
SOFTWARE\\.\
\\( \
Except as contained in this notice, \
the names? \\(?:of the above copyright holders\\|.+?\\) shall not be
used in advertising or otherwise to promote the sale, use or other dealings in
this Software without prior written authorization\\)?"
   ;; "." or "from <copyright holders>."
   ))

(defconst elx-isc-permission-statement-regexp
  (replace-regexp-in-string
   "\s" "[\s\t\n;]+"
   ;; Copyright <YEAR> <OWNER>
   ;;
   "\
Permission to use, copy, modify, and\\(/or\\)? distribute this software \
for any purpose with or without fee is hereby granted, provided \
that the above copyright notice and this permission notice appear \
in all copies\\. \
\
THE SOFTWARE IS PROVIDED [\"'`]*AS IS[\"'`]* AND THE AUTHOR \
DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING \
ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS\\. IN NO \
EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, \
INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER \
RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION \
OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF \
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE\\."))

(defconst elx-cc-permission-statement-regexp
  (replace-regexp-in-string
   "\s" "[\s\t\n;]+"
   ;; This work is
   "\
licensed under the Creative Commons \
\\(Attribution\
\\|Attribution-ShareAlike\
\\|Attribution-NonCommercial\
\\|Attribution-NoDerivs\
\\|Attribution-NonCommercial-ShareAlike\
\\|Attribution-NonCommercial-NoDerivs\
\\) \
\\([0-9.]+\\) .*?Licen[sc]e\\."
   ;; To view a copy of this license, visit"
   ))

(defconst elx-gnu-license-keyword-regexp "\
\\(?:GNU \\(?1:Lesser \\| Library \\|Affero \\|Free \\)? General Public Licen[sc]e\
\\|\\(?4:[laf]?gpl\\)[- ]?\
\\)\
\\(?:\\(?:v\\|version \\)?\\(?2:[0-9.]*[0-9]\\)\\)?\
\\(?3: or \\(?:(at your option) \\)?\\(?:any \\)?later\\(?: version\\)?\\)?")

(defconst elx-gnu-non-standard-permission-statement-alist
  '(("GPL-3+"        . "^;\\{1,4\\} Licensed under the same terms as Emacs")
    ("GPL-2+"        . ";;   :licence:  GPL 2 or later (free software)")
    ("GPL"           . ";; Copyright (c) [-0-9]+ Jason Milkins (GNU/GPL Licence)")
    ))

(defconst elx-non-gnu-license-keyword-alist
  '(("Apache-2.0"    . "apache-2\\.0")
    ("BSD-3-clause"  . "BSD Licen[sc]e 2\\.0")
    ("BSD-3-clause"  . "\\(Revised\\|New\\|Modified\\) BSD\\( Licen[sc]e\\)?")
    ("BSD-2-clause"  . "Simplified BSD\\( Licen[sc]e\\)?")
    ("MIT"           . "mit")
    ("as-is"         . "as-?is")
    ("public-domain" . "public[- ]domain")
    ("WTFPL"         . "WTFPL, grab your copy here: http://sam.zoy.org/wtfpl/")
    ))

(defconst elx-non-gnu-license-keyword-regexp "\
\\`\\(?4:[a-z]+\\)\\(?:\\(?:v\\|version \\)?\\(?2:[0-9.]*[0-9]\\)\\)?\\'")

(defconst elx-permission-statement-alist
  `(("Apache-2.0"    . "^;.* Apache Licen[sc]e, Version 2\\.0")
    ("MIT"           . "^;.* mit licen[sc]e")
    ("GPL-3+"        . "^;; Licensed under the same terms as Emacs\\.$")
    ("WTFPL-2"       . "do what the fuck you want to public licen[sc]e,? version 2")
    ("WTFPL"         . "do what the fuck you want to")
    ("WTFPL"         . "wtf public licen[sc]e")
    ("BSD-2-clause"  . "^;; Simplified BSD Licen[sc]e$")
    ("Artistic-2.0"  . "^;; .*Artistic Licen[sc]e 2\\.0")
    ("public-domain" . "^;.*in\\(to\\)? the public[- ]domain")
    ("public-domain" . "^;+ +Public domain\\.")
    ("as-is"         . "^;.* \\(\\(this\\|the\\) software is \\)\
\\(provided\\|distributed\\) \
\\(by the \\(author?\\|team\\|copyright holders\\)\\( and contributors\\)? \\)?\
[\"'`]+as\\(\n;;\\)?[- ]is[\"'`]")
    ))

(defun elx-license (&optional file dir package-name)
  "Attempt to return the license used for the file FILE.
Or the license used for the file that is being visited in the
current buffer if FILE is nil.

*** A value is returned in the hope that it will be useful, but
*** WITHOUT ANY WARRANTY; without even the implied warranty of
*** MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

This function completely ignores and \"LICENSE\" or similar file
in the proximity of FILE.  The returned value is solely based on
the contents of FILE itself.

The license is determined from the permission statement, if any.
Otherwise the value of the \"License\" header keyword is
considered.  An effort is made to normalize the returned value.

*** However this function does not always return the correct
*** value and the returned value is not legal advice.

Note in particular that if this function returns nil, then that
merely merely means that it is not known what license applies.
This may be because the library lacks a permission statement
altogether (possibly because an accompanying \"LICENSE\" file
is considered sufficient by the upstream), but it may also be
because this function does not attempt to detect the used
non-standard and/or non-fsf permission statement, or because
of typos in the statement, or for a number of other reasons."
  (lm-with-file file
    (cl-flet ((format-gnu-abbrev
               (&optional object)
               (let ((abbrev  (match-string 1 object))
                     (version (match-string 2 object))
                     (later   (match-string 3 object))
                     (prefix  (match-string 4 object)))
                 (concat (if prefix
                             (upcase prefix)
                           (pcase abbrev
                             ("Lesser "  "LGPL")
                             ("Library " "LGBL")
                             ("Affero "  "AGPL")
                             ("Free "    "FDL")
                             (`nil       "GPL")))
                         (and version (concat "-" version))
                         (and later "+"))))
              (format-bsd-abbrev
               (&optional object)
               (format "BSD-%s-clause"
                       (cond ((match-string 4 object) 4)
                             ((match-string 3 object) 3)
                             (t                       2))))
              (format-mit-abbrev
               (&optional object)
               (format "MIT (%s)"
                       (if (match-string 1 object) "expat" "x11")))
              (format-isc-abbrev
               (&optional object)
               (format "ISC (%s)"
                       (if (match-string 1 object) "and/or" "and")))
              (format-cc-abbrev
               (&optional object)
               (let ((license (match-string 1 object))
                     (version (match-string 2 object)))
                 (format "CC-%s-%s"
                         (pcase license
                           ("Attribution"                          "BY")
                           ("Attribution-ShareAlike"               "BY-SA")
                           ("Attribution-NonCommercial"            "BY-NC")
                           ("Attribution-NoDerivs"                 "BY-ND")
                           ("Attribution-NonCommercial-ShareAlike" "BY-NC-SA")
                           ("Attribution-NonCommercial-NoDerivs"   "BY-NC-ND"))
                         version))))
      (let ((bound nil) ; (lm-code-start)) some put it at eof
            (case-fold-search t))
        (or (and (re-search-forward elx-gnu-permission-statement-regexp bound t)
                 (format-gnu-abbrev))
            (and (re-search-forward elx-bsd-permission-statement-regexp bound t)
                 (format-bsd-abbrev))
            (and (re-search-forward elx-mit-permission-statement-regexp bound t)
                 (format-mit-abbrev))
            (and (re-search-forward elx-isc-permission-statement-regexp bound t)
                 (format-isc-abbrev))
            (and (re-search-forward elx-cc-permission-statement-regexp bound t)
                 (format-cc-abbrev))
            (-when-let (license (lm-header "Licen[sc]e"))
              (or (and (string-match elx-gnu-license-keyword-regexp license)
                       (format-gnu-abbrev license))))
            (elx-licensee dir)
            ;; FIXME Github used the above tool too.  But for some
            ;; reason they get better results than I do.  So ask them
            ;; too.
            (and package-name
                 (elx-licensee-github package-name))
            (car (cl-find-if (pcase-lambda (`(,_ . ,re))
                               (re-search-forward re bound t))
                             elx-gnu-non-standard-permission-statement-alist))
            (-when-let (license (lm-header "Licen[sc]e"))
              (or (car (cl-find-if (pcase-lambda (`(,_ . ,re))
                                     (string-match re license))
                                   elx-non-gnu-license-keyword-alist))
                  (and (string-match elx-non-gnu-license-keyword-regexp license)
                       (format-gnu-abbrev license))))
            (and ;; Some libraries are releases "under the *GPL and
                 ;; "<other license>", while the GPL is mentioned in
                 ;; a way the above code does not recognize.  Return
                 ;; nil instead of "<other license>" in such cases.
                 (not (re-search-forward elx-gnu-license-keyword-regexp bound t))
                 (car (cl-find-if (pcase-lambda (`(,_ . ,re))
                                    (re-search-forward re bound t))
                                  elx-permission-statement-alist))))))))

(defun elx-licensee (&optional directory-or-file)
  ;; See http://ben.balter.com/licensee/.
  (-when-let (lines (ignore-errors
                      (process-lines "licensee"
                                     (or directory-or-file default-directory))))
    (elx--licensee-abbrev
     (substring (cl-find-if (lambda (s) (string-prefix-p "License: " s))
                            lines)
                9))))

(defun elx-licensee-github (name)
  (-when-let (pkg (epkg name))
    (and (cl-typep pkg 'epkg-github-package)
         (--> (format "/repos/%s/%s"
                      (oref pkg upstream-user)
                      (oref pkg upstream-name))
              (let ((ghub-extra-headers
                     '(("Accept"
                        . "application/vnd.github.drax-preview+json"))))
                (ghub-get it))
              (cdr (assq 'license it))
              (cdr (assq 'name it))
              (elx--licensee-abbrev it)))))

(defun elx--licensee-abbrev (license)
  (pcase license
    ("Apache License 2.0"                          "Apache-2.0")
    ("Artistic License 2.0"                        "Artistic-2.0")
    ("BSD 2-clause \"Simplified\" License"         "BSD-2-clause")
    ("BSD 3-clause \"New\" or \"Revised\" License" "BSD-3-clause")
    ("Do What The F*ck You Want To Public License" "WTFPL")
    ("Eclipse Public License 1.0"                  "EPL-1.0")
    ("GNU Affero General Public License v3.0"      "AGPL-3")
    ("GNU General Public License v2.0"             "GPL-2")
    ("GNU General Public License v3.0"             "GPL-3")
    ("GNU Lesser General Public License v2.1"      "LGPL-2.1")
    ("GNU Lesser General Public License v3.0"      "LGPL-3")
    ("ISC License"                                 "ISC")
    ("MIT License"                                 "MIT")
    ("Mozilla Public License 2.0"                  "MPL-2")
    ("The Unlicense"                               "unlicense")
    ("Other"                                       nil)
    (""                                            nil) ; bug
    (_                                             license)))

(defcustom elx-license-url-alist
  '(("GPL-3"         . "http://www.fsf.org/licensing/licenses/gpl.html")
    ("GPL-2"         . "http://www.gnu.org/licenses/old-licenses/gpl-2.0.html")
    ("GPL-1"         . "http://www.gnu.org/licenses/old-licenses/gpl-1.0.html")
    ("LGPL-3"        . "http://www.fsf.org/licensing/licenses/lgpl.html")
    ("LGPL-2.1"      . "http://www.gnu.org/licenses/old-licenses/lgpl-2.1.html")
    ("LGPL-2.0"      . "http://www.gnu.org/licenses/old-licenses/lgpl-2.0.html")
    ("AGPL-3"        . "http://www.fsf.org/licensing/licenses/agpl.html")
    ("FDL-1.2"       . "http://www.gnu.org/licenses/old-licenses/fdl-1.2.html")
    ("FDL-1.1"       . "http://www.gnu.org/licenses/old-licenses/fdl-1.1.html"))
  "List of FSF license to canonical license url mappings.
Each entry has the form (LICENSE . URL) where LICENSE is the
abbreviation of a license published by the Free Software
Foundation in the form \"<ABBREV>-<VERSION>\" and URL the
canonical url to the license."
  :group 'elx
  :type '(repeat (cons (string :tag "License")
                       (string :tag "URL"))))

(defun elx-license-url (license)
  "Return the canonical url to the FSF license LICENSE.
The license is looked up in the variable `elx-license-url'.
If no matching entry exists then return nil."
  (cdr (assoc license elx-license-url-alist)))

;;; Extract Dates

(defun elx-created (&optional file)
  "Return the created date given in file FILE.
Or of the current buffer if FILE is equal to `buffer-file-name'
or is nil.  The date is returned as YYYYMMDD or if not enough
information is available YYYYMM or YYYY.  The date is taken from
the \"Created\" header keyword, or if that doesn't work from the
copyright line."
  (lm-with-file file
    (or (elx--date-1 (lm-creation-date))
        (elx--date-1 (elx--date-copyright)))))

(defun elx-updated (&optional file)
  "Return the updated date given in file FILE.
Or of the current buffer if FILE is equal to `buffer-file-name'
or is nil.  The date is returned as YYYYMMDD or if not enough
information is available YYYYMM or YYYY.  The date is taken from
the \"Updated\" or \"Last-Updated\" header keyword."
  (lm-with-file file
    (elx--date-1 (lm-header "\\(last-\\)?updated"))))

;; Yes, I know.
(defun elx--date-1 (string)
  (when (stringp string)
    (let ((ymd "\
\\([0-9]\\{4,4\\}\\)\\(?:[-/.]?\
\\([0-9]\\{1,2\\}\\)\\(?:[-/.]?\
\\([0-9]\\{1,2\\}\\)?\\)?\\)")
          (dmy "\
\\(?3:[0-9]\\{1,2\\}\\)\\(?:[-/.]?\\)\
\\(?2:[0-9]\\{1,2\\}\\)\\(?:[-/.]?\\)\
\\(?1:[0-9]\\{4,4\\}\\)"))
      (or (elx--date-2 string ymd t)
          (elx--date-2 string dmy t)
          (let ((a (elx--date-3 string))
                (b (or (elx--date-2 string ymd nil)
                       (elx--date-2 string dmy nil))))
            (cond ((not a) b)
                  ((not b) a)
                  ((> (length a) (length b)) a)
                  ((> (length b) (length a)) b)
                  (t a)))))))
  
(defun elx--date-2 (string regexp anchored)
  (when (string-match (if anchored (format "^%s$" regexp) regexp) string)
    (let ((m  (match-string 2 string))
          (d  (match-string 3 string)))
      (concat (match-string 1 string)
              (and m d (concat (if (= (length m) 2) m (concat "0" m))
                               (if (= (length d) 2) d (concat "0" d))))))))

(defun elx--date-3 (string)
  (let ((time (mapcar (lambda (e) (or e 0))
                      (butlast (ignore-errors (parse-time-string string))))))
    (when (and time (not (= (nth 5 time) 0)))
      (format-time-string
       (if (and (> (nth 4 time) 0)
                (> (nth 3 time) 0))
           "%Y%m%d"
         ;; (format-time-string "%Y" (encode-time x x x 0 0 2012))
         ;; => "2011"
         (setcar (nthcdr 3 time) 1)
         (setcar (nthcdr 4 time) 1)
         "%Y")
       (apply 'encode-time time)
       t))))

;; FIXME implement range extraction in lm-crack-copyright
(defun elx--date-copyright ()
  (let ((lm-copyright-prefix "^\\(;+[ \t]\\)+Copyright \\((C) \\)?"))
    (when (lm-copyright-mark)
      (cadr (lm-crack-copyright)))))

;;; Extract People

(defcustom elx-remap-names nil
  "List of names that should be replaced or dropped by `elx-crack-address'.
If function `elx-crack-address' is called with a non-nil SANITIZE argument
it checks this variable to determine if names should be dropped from the
return value or replaced by another.  If the cdr of an entry is nil then
the keyword is dropped; otherwise it will be replaced with the keyword in
the cadr."
  :group 'elx
  :type '(repeat (list string (choice (const  :tag "drop" nil)
                                      (string :tag "replacement")))))

;; Yes, I know.
(defun elx-crack-address (x)
  "Split up an email address X into full name and real email address.
The value is a cons of the form (FULLNAME . ADDRESS)."
  (let (name mail)
    (cond ((string-match (concat "\\(.+\\) "
                                 "?[(<]\\(\\S-+@\\S-+\\)[>)]") x)
           (setq name (match-string 1 x)
                 mail (match-string 2 x)))
          ((string-match (concat "\\(.+\\) "
                                 "[(<]\\(?:\\(\\S-+\\) "
                                 "\\(?:\\*?\\(?:AT\\|[.*]\\)\\*?\\) "
                                 "\\(\\S-+\\) "
                                 "\\(?:\\*?\\(?:DOT\\|[.*]\\)\\*? \\)?"
                                 "\\(\\S-+\\)\\)[>)]") x)
           (setq name (match-string 1 x)
                 mail (concat (match-string 2 x) "@"
                              (match-string 3 x) "."
                              (match-string 4 x))))
          ((string-match (concat "\\(.+\\) "
                                 "[(<]\\(?:\\(\\S-+\\) "
                                 "\\(?:\\*?\\(?:AT\\|[.*]\\)\\*?\\) "
                                 "\\(\\S-+\\)[>)]\\)") x)
           (setq name (match-string 1 x)
                 mail (concat (match-string 2 x) "@"
                              (match-string 3 x))))
          ((string-match (concat "\\(\\S-+@\\S-+\\) "
                                 "[(<]\\(.*\\)[>)]") x)
           (setq name (match-string 2 x)
                 mail (match-string 1 x)))
          ((string-match "\\S-+@\\S-+" x)
           (setq mail x))
          (t
           (setq name x)))
    (setq name (and (stringp name)
                    (string-match "^ *\\([^:0-9<@>]+?\\) *$" name)
                    (match-string 1 name)))
    (setq mail (and (stringp mail)
                    (string-match
                     (concat "^\\s-*\\("
                             "[a-z0-9!#$%&'*+/=?^_`{|}~-]+"
                             "\\(?:\.[a-z0-9!#$%&'*+/=?^_`{|}~-]+\\)*@"
                             "\\(?:[a-z0-9]\\(?:[a-z0-9-]*[a-z0-9]\\)?\.\\)+"
                             "[a-z0-9]\\(?:[a-z0-9-]*[a-z0-9]\\)?"
                             "\\)\\s-*$") mail)
                    (downcase (match-string 1 mail))))
    (let ((elt (assoc name elx-remap-names)))
      (when elt
        (setq name (cadr elt))))
    (when (or name mail)
      (cons name mail))))

(defun elx-people (header file)
  (lm-with-file file
    (let (people)
      (dolist (p (lm-header-multiline header))
        (when p
          (setq p (elx-crack-address p))
          (when p
            (push p people))))
      (nreverse people))))

(defun elx-authors (&optional file)
  "Return the author list of file FILE.
Or of the current buffer if FILE is equal to `buffer-file-name'
or is nil.  Each element of the list is a cons; the car is the
full name, the cdr is an email address."
  (elx-people "authors?" file))

(defun elx-maintainers (&optional file)
  "Return the maintainer list of file FILE.
Or of the current buffer if FILE is equal to `buffer-file-name'
or is nil.  Each element of the list is a cons; the car is the
full name, the cdr is an email address.  If there is no
maintainer list then return the author list."
  (or (elx-people "maintainers?" file)
      (elx-authors file)))

(defun elx-adapted-by (&optional file)
  "Return the list of people who have adapted file FILE
Or of the current buffer if FILE is equal to `buffer-file-name'
or is nil.  Each element of the list is a cons; the car is the
full name, the cdr is an email address."
  (elx-people "adapted-by" file))

(provide 'elx)
;; Local Variables:
;; indent-tabs-mode: nil
;; End:
;;; elx.el ends here
