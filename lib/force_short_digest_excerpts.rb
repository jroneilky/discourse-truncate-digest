# frozen_string_literal: true
  require "cgi"

  module ::ForceShortDigestExcerpts
    def email_excerpt(html_arg, post = nil)
      return "".html_safe if html_arg.blank?

      begin
        # 0. Run through core's own sanitation pipeline first: strips secure
        #    uploads, fires the :reduce_cooked plugin event, resolves links.
        #    Falls back to raw input if that ever raises.
        html = (PrettyText.format_for_email(html_arg.to_s, post) rescue html_arg.to_s)

        # 1. Insert a space after every closing tag and after <br>/<hr> so
        #    words from adjacent elements (tables, quotes, code, etc.) don't
        #    get concatenated once tags are stripped.
        spaced = html.gsub(%r{</[a-zA-Z0-9]+>}, '\0 ')
                     .gsub(%r{<br\s*/?>|<hr\s*/?>}i, ' ')

        # 2. Strip tags, decode entities, collapse whitespace.
        plain = ActionController::Base.helpers.strip_tags(spaced)
        plain = CGI.unescapeHTML(plain)
        plain = plain.gsub(/\s+/, ' ').strip

        # 3. Hard character truncation (exact length via a real, tunable
        #    site setting instead of dead-code detection).
        max_len = SiteSetting.digest_post_truncation_length
        truncated = plain.truncate(max_len, omission: '...')

        ERB::Util.html_escape(truncated).html_safe
      rescue => e
        Rails.logger.warn("[discourse-digest-strict-truncation] #{e.class}: #{e.message}")
        "".html_safe # never raise inside a mailer helper
      end
    end
  end

  ::UserNotificationsHelper.prepend(ForceShortDigestExcerpts)
end
