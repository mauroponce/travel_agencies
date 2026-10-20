class AddCommercialPhoneToMemberships < ActiveRecord::Migration[8.1]
  def up
    add_column :memberships, :commercial_phone, :string

    execute <<~SQL.squish
      UPDATE memberships
      SET commercial_phone = users.phone
      FROM users
      WHERE memberships.user_id = users.id
        AND users.phone IS NOT NULL
        AND users.phone <> ''
    SQL
  end

  def down
    remove_column :memberships, :commercial_phone
  end
end
