import { useEffect, useState } from 'react'
import client from './api/client'
import './App.css'

function App() {
  const [apiStatus, setApiStatus] = useState('checking…')
  const [movies, setMovies] = useState([])

  useEffect(() => {
    client
      .get('/api/v1/movies')
      .then((res) => {
        setApiStatus('connected')
        setMovies(res.data.movies || [])
      })
      .catch(() =>
        setApiStatus('unreachable - run `make up` to start the backend')
      )
  }, [])

  const apiUrl = import.meta.env.VITE_API_URL || 'http://localhost:3000'

  return (
    <>
      <header id="app-header">
        <h1>Hypertube</h1>
        <p className="tagline">Search · Download · Stream</p>
      </header>

      <main id="app-main">
        <section className="status-card">
          <h2>API Status</h2>
          <span className={`badge ${apiStatus === 'connected' ? 'badge--ok' : 'badge--err'}`}>
            {apiStatus}
          </span>
          <p className="hint">
            Backend: <code>{apiUrl}</code>
            {' · '}
            <a href={`${apiUrl}/api-docs`} target="_blank" rel="noreferrer">
              Swagger docs
            </a>
          </p>
        </section>

        <section className="movies-section">
          <h2>Top Movies</h2>
          {movies.length === 0 ? (
            <p className="empty">
              No movies yet - implement the torrent sources in the Rails API to populate this list.
            </p>
          ) : (
            <ul className="movie-grid">
              {movies.map((m) => (
                <li key={m.id} className="movie-card">
                  {m.name}
                </li>
              ))}
            </ul>
          )}
        </section>
      </main>

      <footer id="app-footer">
        <p>Hypertube &mdash; 42 School Project</p>
      </footer>
    </>
  )
}

export default App
