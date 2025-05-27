<<<<<<< HEAD
class ApplicationRecord < ActiveRecord::Base
=======
# frozen_string_literal: true

class ApplicationRecord < ActiveRecord::Base
  include DataPortable

>>>>>>> origin/feat/claude-code-action
  primary_abstract_class
end
