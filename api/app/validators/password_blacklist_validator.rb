require "set"

class PasswordBlacklistValidator < ActiveModel::EachValidator
  PASSWORD_BLACKLIST_PATH = Rails.root.join("config/password_blacklists/francais.txt")

  def validate_each(record, attribute, value)
    return if value.blank?
    return unless self.class.blacklisted?(value)

    record.errors.add(attribute, :blacklisted, message: options[:message] || "is too common")
  end

  def self.blacklisted?(password)
    blacklist.include?(normalize(password))
  end

  def self.blacklist
    @blacklist ||= begin
      words = Set.new

      File.foreach(PASSWORD_BLACKLIST_PATH, chomp: true) do |word|
        normalized_word = normalize(word)
        words.add(normalized_word) if normalized_word.present?
      end

      words.freeze
    end
  end

  def self.normalize(value)
    ActiveSupport::Inflector.transliterate(value.to_s).strip.downcase
  end
end
