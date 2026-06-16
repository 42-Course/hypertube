import { Navigate, Route, Routes } from 'react-router-dom'
import AppLayout from '../components/layout/AppLayout'
import ProtectedRoute from './ProtectedRoute'
import AuthCallbackPage from '../pages/AuthCallbackPage'
import LoginPage from '../pages/LoginPage'
import MovieDetailsPage from '../pages/MovieDetailsPage'
import MoviesPage from '../pages/MoviesPage'
import ProfilePage from '../pages/ProfilePage'
import RegisterPage from '../pages/RegisterPage'

function AppRouter() {
  return (
    <Routes>
      <Route path="/" element={<Navigate to="/login" replace />} />
      <Route path="/auth/callback" element={<AuthCallbackPage />} />
      <Route path="/login" element={<LoginPage />} />
      <Route path="/register" element={<RegisterPage />} />
      <Route
        path="/movies"
        element={
          <ProtectedRoute>
            <AppLayout>
              <MoviesPage />
            </AppLayout>
          </ProtectedRoute>
        }
      />
      <Route
        path="/movies/:movieId"
        element={
          <ProtectedRoute>
            <AppLayout>
              <MovieDetailsPage />
            </AppLayout>
          </ProtectedRoute>
        }
      />
      <Route
        path="/profile"
        element={
          <ProtectedRoute>
            <AppLayout>
              <ProfilePage />
            </AppLayout>
          </ProtectedRoute>
        }
      />
    </Routes>
  )
}

export default AppRouter
