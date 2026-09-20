# frozen_string_literal: true

# name: discourse-digest-strict-truncation
# about: Hard-truncates post/reply excerpts in digest (activity summary) emails to a configurable number of characters. Topic titles are not affected.
# version: 0.2
# authors: jroneilky
# url: https://github.com/jroneilky/discourse-digest-strict-truncation
# required_version: 3.0.0

enabled_site_setting :digest_strict_truncation_enabled

module ::DigestStrictTruncation
  PLUGIN_NAME = "discourse-digest-strict-truncation"

  # Only block-level closers get a space injected. Injecting after *every*
  # closing tag splits words that contain inline markup ("wo<b>r</b>d").
  BLOCK_CLOSE =
    %r{</(?:p|div|li|ul|ol|dl|dd|dt|blockquote|aside|section|article|header|footer|
          h[1-6]|pre|table|thead|tbody|tr|td|th|figure|figcaption|details|summary)>}xi

  LINE_BREAK = %r{<br[^>]*>|<hr[^>]*>}i

  class << self
    def max_length
      len = SiteSetting.digest_strict_truncation_length.to_i
      len < 5 ? 50 : len
    end

    # HTML -> single-line plain text, entities decoded exactly once.
    def to_plain_text(html)
      spaced = html.to_s.gsub(BLOCK_CLOSE) { |tag| "#{tag} " }.gsub(LINE_BREAK, " ")

      doc = Nokogiri::HTML5.fragment(spaced)
      doc.css("script, style").each(&:remove)
      # Emoji are <img class="emoji" alt=":smile:"> in cooked HTML; keep the alt
      # text instead of silently dropping them mid-sentence.
      doc
        .css("img.emoji")
        .each do |img|
          alt = img["alt"].to_s
          img.replace(Nokogiri::XML::Text.new(alt.present? ? " #{alt} " : " ", img.document))
        end

      doc.text.gsub(/[[:space:]]+/, " ").strip
    end

    # Returns an html_safe, escaped, hard-truncated string.
    def truncate_html(html)
      plain = to_plain_text(html)
      return "".html_safe if plain.blank?

      ERB::Util.html_escape(plain.truncate(max_length, omission: "…")).html_safe
    rescue => e
      warn_error(e, "truncate_html")
      # Fail closed: a crude strip is still better than emitting the full post.
      crude = html.to_s.gsub(/<[^>]*>/, " ").gsub(/[[:space:]]+/, " ").strip
      ERB::Util.html_escape(crude.truncate(max_length, omission: "…")).html_safe
    end

    def warn_error(error, context)
      Rails.logger.error("[#{PLUGIN_NAME}] #{context}: #{error.class}: #{error.message}")
    end
  end

  module EmailExcerptOverride
    # Core signature (Discourse 3.x): email_excerpt(html_arg, post = nil).
    # Accept anything so a future core signature change can't raise ArgumentError
    # here; zsuper forwards whatever was passed.
    def email_excerpt(html_arg = nil, *args, **kwargs, &blk)
      return super unless SiteSetting.digest_strict_truncation_enabled
      return "".html_safe if html_arg.blank?

      # Let core do the sanitation it owns: first_paragraphs_from,
      # PrettyText.format_for_email (secure uploads, :reduce_cooked, link
      # resolution). We only post-process the result.
      html =
        begin
          super.to_s
        rescue => e
          ::DigestStrictTruncation.warn_error(e, "super")
          html_arg.to_s
        end

      ::DigestStrictTruncation.truncate_html(html)
    rescue => e
      ::DigestStrictTruncation.warn_error(e, "email_excerpt")
      "".html_safe # never raise inside a mailer
    end
  end
end

after_initialize do
  # UserNotificationsHelper lives in app/helpers, so it is autoloaded and gets
  # reloaded in development (and on some console/runner paths). Without
  # reloadable_patch the prepend is silently dropped after a reload.
  reloadable_patch do
    ::UserNotificationsHelper.prepend(::DigestStrictTruncation::EmailExcerptOverride)

    # UserNotifications (the digest mailer) and UserNotificationRenderer include
    # the helper at boot, i.e. before this runs. Prepending into an
    # already-included module only propagates on Ruby >= 3.1, so patch the
    # including classes directly as well. Harmless if it ends up applied twice:
    # the transform is idempotent.
    ::UserNotifications.prepend(::DigestStrictTruncation::EmailExcerptOverride)
    if defined?(::UserNotificationRenderer)
      ::UserNotificationRenderer.prepend(::DigestStrictTruncation::EmailExcerptOverride)
    end
  end
end
