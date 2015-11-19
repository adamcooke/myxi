module Myxi
  module ViewHelpers

    def myxi_host
      Rails.env.development? ? "ws://localhost:5006" : "#{request.protocol}#{request.host}/pushwss/"
    end

    def myxi_javascript_tag
      "<meta name=\"myxi-host\" content=\"#{myxi_host}\" />".html_safe
    end

  end
end
