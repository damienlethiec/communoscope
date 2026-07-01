class CreateCommunes < ActiveRecord::Migration[8.1]
  def change
    create_table :communes do |t|
      t.string :code_insee, null: false
      t.string :nom, null: false
      t.integer :population

      t.timestamps
    end
    add_index :communes, :code_insee, unique: true
  end
end
