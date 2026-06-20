import { Navigate, Route, Routes } from 'react-router-dom'
import AppLayout from '../components/layout/AppLayout'
import ProtectedRoute from './ProtectedRoute'
import ActivityPage from '../pages/ActivityPage'
import AuthCallbackPage from '../pages/AuthCallbackPage'
import ForgotPasswordPage from '../pages/ForgotPasswordPage'
import LoginPage from '../pages/LoginPage'
import MovieDetailsPage from '../pages/MovieDetailsPage'
import MoviesPage from '../pages/MoviesPage'
import ProfilePage from '../pages/ProfilePage'
import PublicProfilePage from '../pages/PublicProfilePage'
import RegisterPage from '../pages/RegisterPage'
import ResetPasswordPage from '../pages/ResetPasswordPage'
import UsersPage from '../pages/UsersPage'

function AppRouter() {
  return (
    <Routes>
      <Route path="/" element={<Navigate to="/login" replace />} />
      <Route path="/auth/callback" element={<AuthCallbackPage />} />
      <Route path="/login" element={<LoginPage />} />
      <Route path="/register" element={<RegisterPage />} />
      <Route path="/forgot-password" element={<ForgotPasswordPage />} />
      <Route path="/reset-password" element={<ResetPasswordPage />} />
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
      <Route
        path="/users"
        element={
          <ProtectedRoute>
            <AppLayout>
              <UsersPage />
            </AppLayout>
          </ProtectedRoute>
        }
      />
      <Route
        path="/activity"
        element={
          <ProtectedRoute>
            <AppLayout>
              <ActivityPage />
            </AppLayout>
          </ProtectedRoute>
        }
      />
      <Route
        path="/users/:userId"
        element={
          <ProtectedRoute>
            <AppLayout>
              <PublicProfilePage />
            </AppLayout>
          </ProtectedRoute>
        }
      />
    </Routes>
  )
}

export default AppRouter
