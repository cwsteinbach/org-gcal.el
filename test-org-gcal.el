;;; test-org-gcal.el --- Tests for org-gcal.el -*- lexical-binding: t -*-

;; Copyright (C) 2019 Robert Irelan

;; Author: Robert Irelan <rirelan@gmail.com>

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Tests for org-gcal.el

;;; Code:

(require 'org-gcal)
(require 'cl-lib)
(require 'el-mock)

(defconst test-org-gcal-calendar-id "foo@foobar.com")

(defconst test-org-gcal-event-json
  "\
{
 \"kind\": \"calendar#event\",
 \"etag\": \"\\\"12344321\\\"\",
 \"id\": \"foobar1234\",
 \"status\": \"confirmed\",
 \"htmlLink\": \"https://www.google.com/calendar/event?eid=foobareid1234\",
 \"hangoutsLink\": \"https://hangouts.google.com/my-meeting-id\",
 \"location\": \"Foobar's desk\",
 \"created\": \"2019-09-27T20:50:45.000Z\",
 \"updated\": \"2019-10-06T22:59:47.287Z\",
 \"summary\": \"My event summary\",
 \"description\": \"My event description\\n\\nSecond paragraph\",
 \"creator\": {
  \"email\": \"foo@foobar.com\",
  \"displayName\": \"Foo Foobar\"
 },
 \"organizer\": {
  \"email\": \"bar@foobar.com\",
  \"self\": true
 },
 \"start\": {
  \"dateTime\": \"2019-10-06T17:00:00-07:00\"
 },
 \"end\": {
  \"dateTime\": \"2019-10-06T21:00:00-07:00\"
 },
 \"reminders\": {
  \"useDefault\": true
 }
}
")

(defmacro test-org-gcal--with-temp-buffer (contents &rest body)
  "Create a ‘org-mode’ enabled temp buffer with CONTENTS.
BODY is code to be executed within the temp buffer.  Point is
always located at the beginning of the buffer."
  (declare (indent 1) (debug t))
  `(with-temp-buffer
     (org-mode)
     (insert ,contents)
     (goto-char (point-min))
     ,@body))

(defun test-org-gcal--json-read-string (json)
  "Wrap ‘org-gcal--json-read’ to parse a JSON string"
  (with-temp-buffer
    (insert json)
    (org-gcal--json-read)))

(defconst test-org-gcal-event
  (test-org-gcal--json-read-string test-org-gcal-event-json))

(ert-deftest test-org-gcal--update-empty-entry ()
  "Verify that an empty headline is populated correctly from a calendar event
object."
  (test-org-gcal--with-temp-buffer
      "* "
    (org-gcal--update-entry test-org-gcal-calendar-id
                            test-org-gcal-event)
    (org-back-to-heading)
    (let ((elem (org-element-at-point)))
      (should (equal (org-element-property :title elem)
                     "My event summary"))
      (should (equal (org-element-property :ETAG elem)
                     "\"12344321\""))
      (should (equal (org-element-property :LOCATION elem)
                     "Foobar's desk"))
      (should (equal (org-element-property :CALENDAR-ID elem)
                     "foo@foobar.com"))
      (should (equal (org-element-property :ID elem)
                     "foobar1234/foo@foobar.com")))
    ;; Check contents of "org-gcal" drawer
    (re-search-forward ":org-gcal:")
    (let ((elem (org-element-at-point)))
      (should (equal (org-element-property :drawer-name elem)
                     "org-gcal"))
      (should (equal (buffer-substring-no-properties
                      (org-element-property :contents-begin elem)
                      (org-element-property :contents-end elem))
                     "\
<2019-10-06 Sun 17:00-21:00>

My event description

Second paragraph
")))))

(ert-deftest test-org-gcal--update-existing-entry ()
  "Verify that an existing headline is populated correctly from a calendar event
object."
  (test-org-gcal--with-temp-buffer
      "\
* Old event summary
:PROPERTIES:
:ETag:     \"9999\"
:LOCATION: Somewhere else
:calendar-id: foo@foobar.com
:ID:       foobar1234/foo@foobar.com
:END:
:org-gcal:
<9999-10-06 Sun 17:00-21:00>

Old event description
:END:
"
    (org-gcal--update-entry test-org-gcal-calendar-id
                            test-org-gcal-event)
    (org-back-to-heading)
    (let ((elem (org-element-at-point)))
      (should (equal (org-element-property :title elem)
                     "My event summary"))
      (should (equal (org-element-property :ETAG elem)
                     "\"12344321\""))
      (should (equal (org-element-property :LOCATION elem)
                     "Foobar's desk"))
      (should (equal (org-element-property :CALENDAR-ID elem)
                     "foo@foobar.com"))
      (should (equal (org-element-property :ID elem)
                     "foobar1234/foo@foobar.com")))
    ;; Check contents of "org-gcal" drawer
    (re-search-forward ":org-gcal:")
    (let ((elem (org-element-at-point)))
      (should (equal (org-element-property :drawer-name elem)
                     "org-gcal"))
      (should (equal (buffer-substring-no-properties
                      (org-element-property :contents-begin elem)
                      (org-element-property :contents-end elem))
                     "\
<2019-10-06 Sun 17:00-21:00>

My event description

Second paragraph
")))))

(ert-deftest test-org-gcal--update-existing-entry-scheduled ()
  "Same as ‘test-org-gcal--update-existing-entry’, but with SCHEDULED
property."
  (test-org-gcal--with-temp-buffer
      "\
* Old event summary
SCHEDULED: <9999-10-06 Sun 17:00-21:00>
:PROPERTIES:
:ETag:     \"9999\"
:LOCATION: Somewhere else
:calendar-id: foo@foobar.com
:ID:       foobar1234/foo@foobar.com
:END:
:org-gcal:
Old event description
:END:
"
    (org-gcal--update-entry test-org-gcal-calendar-id
                            test-org-gcal-event)
    (org-back-to-heading)
    (let ((elem (org-element-at-point)))
      (should (equal (org-element-property
                      :raw-value
                      (org-element-property :scheduled elem))
                     "<2019-10-06 Sun 17:00-21:00>"))
      (should (equal (org-element-property :title elem)
                     "My event summary"))
      (should (equal (org-element-property :ETAG elem)
                     "\"12344321\""))
      (should (equal (org-element-property :LOCATION elem)
                     "Foobar's desk"))
      (should (equal (org-element-property :CALENDAR-ID elem)
                     "foo@foobar.com"))
      (should (equal (org-element-property :ID elem)
                     "foobar1234/foo@foobar.com")))
    ;; Check contents of "org-gcal" drawer
    (re-search-forward ":org-gcal:")
    (let ((elem (org-element-at-point)))
      (should (equal (org-element-property :drawer-name elem)
                     "org-gcal"))
      (should (equal (buffer-substring-no-properties
                      (org-element-property :contents-begin elem)
                      (org-element-property :contents-end elem))
                     "\
My event description

Second paragraph
")))))

(ert-deftest test-org-gcal--post-at-point-basic ()
  "Verify basic case of ‘org-gcal-post-to-point’."
  (test-org-gcal--with-temp-buffer
      "\
* My event summary
:PROPERTIES:
:ETag:     \"12344321\"
:LOCATION: Foobar's desk
:calendar-id: foo@foobar.com
:ID:       foobar1234/foo@foobar.com
:END:
:org-gcal:
<2019-10-06 Sun 17:00-21:00>

My event description

Second paragraph
:END:
"
    (with-mock
      (stub org-gcal--time-zone => '(0 "UTC"))
      (mock (org-gcal--post-event "2019-10-06T17:00:00Z" "2019-10-06T21:00:00Z"
                                  "My event summary" "Foobar's desk"
                                  "My event description\n\nSecond paragraph"
                                  "foo@foobar.com"
                                  * "\"12344321\"" "foobar1234"
                                  * * *))
      (org-gcal-post-at-point))))

(ert-deftest test-org-gcal--post-at-point-time-date-range ()
  "Verify that entry with a time/date range for its timestamp is parsed by
‘org-gcal-post-to-point’ (see https://orgmode.org/manual/Timestamps.html)."
  (test-org-gcal--with-temp-buffer
      "\
* My event summary
SCHEDULED: <2019-10-06 Sun 17:00>--<2019-10-07 Mon 21:00>
:PROPERTIES:
:ETag:     \"12344321\"
:LOCATION: Foobar's desk
:calendar-id: foo@foobar.com
:ID:       foobar1234/foo@foobar.com
:END:
:org-gcal:
My event description

Second paragraph
:END:
"
    (with-mock
      (stub org-gcal--time-zone => '(0 "UTC"))
      (mock (org-gcal--post-event "2019-10-06T17:00:00Z" "2019-10-07T21:00:00Z"
                                  "My event summary" "Foobar's desk"
                                  "My event description\n\nSecond paragraph"
                                  "foo@foobar.com"
                                  * "\"12344321\"" "foobar1234"
                                  * * *))
      (org-gcal-post-at-point))))

(ert-deftest test-org-gcal--ert-fail ()
  "Test handling of ERT failures in deferred code. Should fail."
  :expected-result :failed
  (with-mock
    (stub request-deferred =>
          (deferred:$
            (deferred:succeed
              (ert-fail "Failure"))
            (deferred:nextc it
              (lambda (_)
                (deferred:succeed "Success")))))
    (should (equal
              (deferred:sync! (request-deferred))
              "Success"))))

;;; Figure out mocking for POST/PATCH followed by GET
;;; - ‘mock‘ might work for this - the argument list must be specified up
;;;   front, but the wildcard ‘*’ can be used to match any value. If that
;;;   doesn’t work, use ‘cl-flet’.

;;; Figure out how to set up org-id for mocking (org-mode tests should help?)
;;; - There are actually no org-mode tests for this.
;;; - Set ‘org-id-locations’ (a hash table). This maps each ID to the file in
;;;   which the ID is found, so a temp file (not just a temp buffer) is needed.
