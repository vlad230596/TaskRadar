import { useState, type FormEvent } from "react";
import { useNavigate } from "react-router-dom";
import { api, UnauthorizedError } from "../lib/api";
import "./LoginPage.css";

export function LoginPage() {
  const navigate = useNavigate();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    setSubmitting(true);
    try {
      // Opt out of the global 401 handler: a wrong password is an expected
      // outcome here, shown inline, not a session expiry to redirect away
      // from (we're already on /login).
      await api.post("/auth/login", { email, password }, { skipUnauthorizedHandler: true });
      navigate("/", { replace: true });
    } catch (err) {
      if (err instanceof UnauthorizedError) {
        setError("Неверный email или пароль");
      } else {
        setError("Не удалось подключиться к серверу. Попробуйте ещё раз.");
      }
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="login-page">
      <form className="login-page__form" onSubmit={handleSubmit}>
        <h1 className="login-page__title">TaskRadar</h1>

        <label className="login-page__field">
          <span>Email</span>
          <input
            type="email"
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            autoComplete="username"
            autoFocus
            required
          />
        </label>

        <label className="login-page__field">
          <span>Пароль</span>
          <input
            type="password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            autoComplete="current-password"
            required
          />
        </label>

        {error && <p className="login-page__error">{error}</p>}

        <button type="submit" disabled={submitting}>
          {submitting ? "Вход…" : "Войти"}
        </button>
      </form>
    </div>
  );
}
