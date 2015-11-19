module Myxi
  class Railtie < ::Rails::Railtie

    initializer 'myxi.initialize' do |app|

      ActiveSupport.on_load(:action_view) do
        require 'myxi/view_helpers'
        ActionView::Base.send :include, Myxi::ViewHelpers
      end

    end

  end
end
