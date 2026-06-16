import { useMemo, useState } from 'react'
import { I18nContext } from './I18nContext'
import { translations } from './translations'

const LANGUAGE_STORAGE_KEY = 'preferred_language'
const DEFAULT_LANGUAGE = 'en'

function resolvePath(source, path) {
  return path.split('.').reduce((value, key) => value?.[key], source)
}

function getInitialLanguage() {
  return localStorage.getItem(LANGUAGE_STORAGE_KEY) || DEFAULT_LANGUAGE
}

export function I18nProvider({ children }) {
  const [language, setLanguageState] = useState(getInitialLanguage)

  function setLanguage(nextLanguage) {
    const safeLanguage = translations[nextLanguage] ? nextLanguage : DEFAULT_LANGUAGE

    localStorage.setItem(LANGUAGE_STORAGE_KEY, safeLanguage)
    setLanguageState(safeLanguage)
  }

  const value = useMemo(() => {
    function t(key, replacements = {}) {
      const translation =
        resolvePath(translations[language], key) ||
        resolvePath(translations[DEFAULT_LANGUAGE], key) ||
        key

      return Object.entries(replacements).reduce(
        (text, [name, value]) => text.replaceAll(`{{${name}}}`, String(value)),
        translation,
      )
    }

    return { language, setLanguage, t }
  }, [language])

  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>
}
