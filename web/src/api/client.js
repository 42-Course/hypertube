import axios from "axios";
import { clearAccessToken, getAccessToken } from "../features/auth/authStorage";

const client = axios.create({
  baseURL: import.meta.env.VITE_API_URL || "http://localhost:3000",
  headers: { "Content-Type": "application/json" },
  timeout: 10000,
});

// Attach OAuth2 Bearer token from localStorage if present
client.interceptors.request.use((config) => {
  const token = getAccessToken();
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

client.interceptors.response.use(
  (response) => response,
  (error) => {
    const url = error.config?.url || "";
    const isSessionEndpoint = url.includes("/api/v1/session");
    if (error.response?.status === 401 && !isSessionEndpoint) {
      clearAccessToken();
      window.location.href = "/login";
    }
    return Promise.reject(error);
  }
);

export default client;
