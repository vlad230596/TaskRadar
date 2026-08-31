import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { createBrowserRouter, RouterProvider } from "react-router-dom";
import { setUnauthorizedHandler } from "./lib/api";
import { LoginPage } from "./pages/LoginPage";
import { BoardPage } from "./pages/BoardPage";
import { ProjectDetailPage } from "./pages/ProjectDetailPage";
import { ArchivePage } from "./pages/ArchivePage";
import "./index.css";

const router = createBrowserRouter([
  { path: "/login", element: <LoginPage /> },
  { path: "/", element: <BoardPage /> },
  { path: "/projects/:id", element: <ProjectDetailPage /> },
  { path: "/archive", element: <ArchivePage /> },
]);

// App-wide reaction to a missing/expired session: any API call that gets a
// 401 sends the user back to the login screen, from wherever they were. See
// src/lib/api.ts for the mechanism and why the login request itself opts out.
setUnauthorizedHandler(() => {
  void router.navigate("/login");
});

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <RouterProvider router={router} />
  </StrictMode>,
);
