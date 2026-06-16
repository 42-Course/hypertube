import { mockMovies } from './mockMovies'

const detailsById = {
  1: {
    length: '2h 16m',
    director: 'Lana Wachowski, Lilly Wachowski',
    producer: 'Joel Silver',
    cast: ['Keanu Reeves', 'Laurence Fishburne', 'Carrie-Anne Moss'],
    summary:
      'A hacker discovers that reality is a simulated prison and joins a rebellion against the machines controlling humanity.',
    subtitles: ['English', 'French'],
    streamStatus: 'Ready to stream',
    comments: [
      { id: 1, author: 'neo42', date: '2026-06-14', content: 'Still a perfect cyberpunk classic.' },
      { id: 2, author: 'trinity', date: '2026-06-15', content: 'The action scenes aged incredibly well.' },
    ],
  },
  2: {
    length: '2h 28m',
    director: 'Christopher Nolan',
    producer: 'Emma Thomas',
    cast: ['Leonardo DiCaprio', 'Joseph Gordon-Levitt', 'Elliot Page'],
    summary:
      'A thief who steals secrets through dream-sharing technology receives a final mission: plant an idea instead of stealing one.',
    subtitles: ['English'],
    streamStatus: 'Preparing stream',
    comments: [
      { id: 1, author: 'dreamer', date: '2026-06-13', content: 'The soundtrack makes the whole movie feel massive.' },
    ],
  },
  3: {
    length: '2h 49m',
    director: 'Christopher Nolan',
    producer: 'Emma Thomas',
    cast: ['Matthew McConaughey', 'Anne Hathaway', 'Jessica Chastain'],
    summary:
      'A team of explorers travels through a wormhole to find a new home for humanity as Earth becomes uninhabitable.',
    subtitles: ['English', 'French', 'Spanish'],
    streamStatus: 'Ready to stream',
    comments: [
      { id: 1, author: 'cooper', date: '2026-06-12', content: 'The docking scene is unreal.' },
      { id: 2, author: 'murph', date: '2026-06-15', content: 'Emotional, technical, and huge.' },
    ],
  },
}

export function getMockMovieDetails(movieId) {
  const movie = mockMovies.find((item) => item.id === Number(movieId))

  if (!movie) {
    return null
  }

  return {
    ...movie,
    ...(detailsById[movie.id] || {
      length: '2h 05m',
      director: 'Unknown director',
      producer: 'Unknown producer',
      cast: ['Main cast unavailable'],
      summary:
        'Detailed metadata will be loaded from the backend once the movie API is connected.',
      subtitles: ['English'],
      streamStatus: 'Preparing stream',
      comments: [],
    }),
  }
}
