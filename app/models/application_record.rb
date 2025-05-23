# frozen_string_literal: true

class ApplicationRecord < ActiveRecord::Base
  include DataPortable
  
  primary_abstract_class
end
