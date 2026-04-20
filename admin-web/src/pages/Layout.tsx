import { NavLink, Outlet, Navigate } from "react-router-dom";
import { useAuth } from "../context/AuthContext";

export function Layout() {
  const { session, loading, signOut, configured } = useAuth();

  if (!configured) {
    return <Navigate to="/login" replace />;
  }
  if (loading) {
    return <p className="muted">Loading…</p>;
  }
  if (!session) {
    return <Navigate to="/login" replace />;
  }

  return (
    <div className="shell">
      <header className="topbar">
        <strong>Blueprint admin</strong>
        <nav className="nav">
          <NavLink to="/catalog" className={({ isActive }) => (isActive ? "active" : "")}>
            Catalog
          </NavLink>
          <NavLink to="/progress" className={({ isActive }) => (isActive ? "active" : "")}>
            Progress seed
          </NavLink>
          <NavLink to="/workouts" className={({ isActive }) => (isActive ? "active" : "")}>
            Workouts
          </NavLink>
        </nav>
        <button type="button" className="linkish" onClick={() => void signOut()}>
          Sign out
        </button>
      </header>
      <main className="main">
        <Outlet />
      </main>
    </div>
  );
}
