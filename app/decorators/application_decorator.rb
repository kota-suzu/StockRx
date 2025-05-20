# frozen_string_literal: true

class ApplicationDecorator < Draper::Decorator
  # Define methods for all decorated objects.
  # Helpers are accessed through `helpers` (aka `h`). For example:
  #
  #   def formatted_created_at
  #     helpers.content_tag :span, class: 'date' do
  #       object.created_at.strftime("%a %m/%d/%y")
  #     end
  #   end
end