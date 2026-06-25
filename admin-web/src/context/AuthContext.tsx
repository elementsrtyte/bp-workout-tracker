import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import {
  authConfigured,
  loadStoredSession,
  refreshStoredSession,
  saveSession,
  signInWithPassword,
  type AuthSession,
} from "../lib/auth";

type AuthContextValue = {
  session: AuthSession | null;
  loading: boolean;
  signIn: (email: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
  configured: boolean;
};

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<AuthSession | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!authConfigured) {
      setLoading(false);
      return;
    }
    void (async () => {
      const stored = loadStoredSession();
      if (!stored?.refresh_token) {
        setLoading(false);
        return;
      }
      try {
        const next = await refreshStoredSession(stored.refresh_token);
        saveSession(next);
        setSession(next);
      } catch {
        saveSession(null);
      } finally {
        setLoading(false);
      }
    })();
  }, []);

  const signIn = useCallback(async (email: string, password: string) => {
    const next = await signInWithPassword(email, password);
    saveSession(next);
    setSession(next);
  }, []);

  const signOut = useCallback(async () => {
    saveSession(null);
    setSession(null);
  }, []);

  const value = useMemo(
    () => ({
      session,
      loading,
      signIn,
      signOut,
      configured: authConfigured,
    }),
    [session, loading, signIn, signOut]
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth outside AuthProvider");
  return ctx;
}
