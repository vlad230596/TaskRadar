import { useEffect, useState, type FormEvent } from "react";
import { Link, useNavigate } from "react-router-dom";
import { api, ApiError } from "../lib/api";
import type { Project, Task } from "../lib/types";
import { ProjectColumn } from "../components/ProjectColumn";
import "./BoardPage.css";

type TaskFetchState = { tasks: Task[] } | { failed: true };

export function BoardPage() {
  const navigate = useNavigate();
  const [projects, setProjects] = useState<Project[] | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [tasksByProject, setTasksByProject] = useState<Record<string, TaskFetchState>>({});
  const [loggingOut, setLoggingOut] = useState(false);
  const [newProjectName, setNewProjectName] = useState("");
  const [creatingProject, setCreatingProject] = useState(false);
  const [createError, setCreateError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;

    async function loadTasksFor(project: Project) {
      try {
        const tasks = await api.get<Task[]>(`/projects/${project.id}/tasks`);
        if (cancelled) return;
        setTasksByProject((prev) => ({ ...prev, [project.id]: { tasks } }));
      } catch (err) {
        if (cancelled) return;
        // A 401 here already triggered the global redirect to /login; no
        // need to also flag this column as broken on the way out.
        if (err instanceof ApiError && err.status === 401) return;
        setTasksByProject((prev) => ({ ...prev, [project.id]: { failed: true } }));
      }
    }

    async function load() {
      try {
        const fetchedProjects = await api.get<Project[]>("/projects");
        if (cancelled) return;
        setProjects(fetchedProjects);
        await Promise.all(fetchedProjects.map(loadTasksFor));
      } catch (err) {
        if (cancelled) return;
        if (err instanceof ApiError && err.status === 401) return;
        setLoadError("Не удалось загрузить проекты. Попробуйте обновить страницу.");
      }
    }

    void load();
    return () => {
      cancelled = true;
    };
  }, []);

  async function handleCreateProject(event: FormEvent) {
    event.preventDefault();
    const name = newProjectName.trim();
    if (!name) return;
    setCreatingProject(true);
    setCreateError(null);
    try {
      const project = await api.post<Project>("/projects", { name });
      // New project has no tasks yet -- seed its entry directly instead of
      // triggering a fetch, so its column doesn't sit on "загрузка…" forever
      // (the initial-load effect only fetches tasks for projects it knew
      // about at mount time).
      setProjects((prev) => (prev ? [...prev, project] : [project]));
      setTasksByProject((prev) => ({ ...prev, [project.id]: { tasks: [] } }));
      setNewProjectName("");
    } catch {
      setCreateError("Не удалось создать проект.");
    } finally {
      setCreatingProject(false);
    }
  }

  async function handleLogout() {
    setLoggingOut(true);
    try {
      await api.post("/auth/logout", undefined, { skipUnauthorizedHandler: true });
    } finally {
      navigate("/login", { replace: true });
    }
  }

  return (
    <div className="board-page">
      <header className="board-page__header">
        <h1 className="board-page__logo">TaskRadar</h1>
        <div className="board-page__header-actions">
          <Link to="/archive" className="board-page__archive-link">
            Архив
          </Link>
          <button className="board-page__logout" onClick={() => void handleLogout()} disabled={loggingOut}>
            Выйти
          </button>
        </div>
      </header>

      {loadError && <p className="board-page__error">{loadError}</p>}

      {!loadError && projects === null && <p className="board-page__note">Загрузка…</p>}

      {!loadError && projects !== null && (
        <>
          <form className="board-page__new-project" onSubmit={(event) => void handleCreateProject(event)}>
            <input
              type="text"
              placeholder="Новый проект…"
              value={newProjectName}
              onChange={(event) => setNewProjectName(event.target.value)}
              disabled={creatingProject}
            />
            <button type="submit" disabled={creatingProject || !newProjectName.trim()}>
              + Новый проект
            </button>
          </form>

          {createError && <p className="board-page__error board-page__error--inline">{createError}</p>}

          {projects.length === 0 ? (
            <p className="board-page__note">Проектов пока нет.</p>
          ) : (
            <div className="board-page__board">
              {projects.map((project) => {
                const state = tasksByProject[project.id];
                return (
                  <ProjectColumn
                    key={project.id}
                    project={project}
                    tasks={state && "tasks" in state ? state.tasks : undefined}
                    failed={Boolean(state && "failed" in state)}
                  />
                );
              })}
            </div>
          )}
        </>
      )}
    </div>
  );
}
