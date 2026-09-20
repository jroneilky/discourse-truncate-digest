# frozen_string_literal: true
# name: discourse-digest-strict-truncation
# about: Strictly truncates digest email post/reply excerpts
# version: 0.4
# authors: you
# url: https://github.com/yourname/discourse-digest-strict-truncation

require_relative "lib/force_short_digest_excerpts"

after_initialize do
  ::UserNotificationsHelper.prepend(ForceShortDigestExcerpts)
end
