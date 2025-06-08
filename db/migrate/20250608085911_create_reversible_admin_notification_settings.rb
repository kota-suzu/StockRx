class CreateReversibleAdminNotificationSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :reversible_admin_notification_settings do |t|
      t.timestamps
    end
  end
end
