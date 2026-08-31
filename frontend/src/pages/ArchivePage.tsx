import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { api, ApiError } from "../lib/api";
import type { Project } from "../lib/types";
import "./ArchivePage.css";

type LoadState = "loading" | "ready" | "error";

function formatDate(iso: string): string {
  const date = new Date(iso);
  const day = String(date.getDate()).padStart(2, "0");
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const year = date.getFullYear();
  return `${day}.${month}.${year}`;
}

/**
 * Low-traffic recovery/cleanup view for archived projects -- not a working
 * view, so no tasks/notes shown here, just enough to recognize a project and
 * decide whether to bring it back or delete it for good.
 */
export function ArchivePage() {
  const [projects, setProjects] = useState<Project[] | null>(null);
  const [loadState, setLoadState] = useState<LoadState>("loading");
  // Per-project in-flight/error state, keyed by project id, so one project's
  // action failing doesn't affect the others in the list.
  const [busyId, setBusyId] = useState<string | null>(null);
  const [rowErrors, setRowErrors] = useState<Record<string, string>>({});

  useEffect(() => {
    let cancelled = false;

    async function load() {
      try {
        const fetched = await api.get<Project[]>("/projects?archived=true");
        if (cancelled) return;
        setProjects(fetched);
        setLoadState("ready");
      } catch (err) {
        if (cancelled) return;
        if (err instanceof ApiError && err.status === 401) return;
        setLoadState("error");
      }
    }

    void load();
    return () => {
      cancelled = true;
    };
  }, []);

  function clearRowError(id: string) {
    setRowErrors((prev) => {
      if (!(id in prev)) return prev;
      const next = { ...prev };
      delete next[id];
      return next;
    });
  }

  async function handleUnarchive(project: Project) {
    setBusyId(project.id);
    clearRowError(project.id);
    try {
      await api.post(`/projects/${project.id}/unarchive`);
      setProjects((prev) => (prev ? prev.filter((p) => p.id !== project.id) : prev));
    } catch {
      setRowErrors((prev) => ({ ...prev, [project.id]: "Не удалось разархивировать проект." }));
    } finally {
      setBusyId(null);
    }
  }

  async function handleDeleteForever(project: Project) {
    const confirmed = window.confirm(
      `Удалить проект «${project.name}» навсегда? Это необратимо и удалит все его задачи и заметки.`,
    );
    if (!confirmed) return;

    setBusyId(project.id);
    clearRowError(project.id);
    try {
      await api.delete(`/projects/${project.id}`);
      setProjects((prev) => (prev ? prev.filter((p) => p.id !== project.id) : prev));
    } catch {
      setRowErrors((prev) => ({ ...prev, [project.id]: "Не удалось удалить проект." }));
    } finally {
      setBusyId(null);
    }
  }

  return (
    <div className="archive-page">
      <Link to="/" className="archive-page__back">
        ← Доска
      </Link>

      <h1 className="archive-page__title">Архив</h1>

      {loadState === "loading" && <p className="archive-page__note">Загрузка…</p>}
      {loadState === "error" && (
        <p className="archive-page__error">Не удалось загрузить архив. Попробуйте обновить страницу.</p>
      )}

      {loadState === "ready" && projects !== null && projects.length === 0 && (
        <p className="archive-page__note">Архив пуст.</p>
      )}

      {loadState === "ready" && projects !== null && projects.length > 0 && (
        <div className="archive-page__list">
          {projects.map((project) => (
            <div key={project.id} className="archive-item">
              <div className="archive-item__info">
                <span className="archive-item__name">{project.name}</span>
                {project.archivedAt && (
                  <span className="archive-item__date">в архиве с {formatDate(project.archivedAt)}</span>
                )}
              </div>
              <div className="archive-item__actions">
                <button
                  type="button"
                  className="archive-item__unarchive"
                  disabled={busyId === project.id}
                  onClick={() => void handleUnarchive(project)}
                >
                  Разархивировать
                </button>
                <button
                  type="button"
                  className="archive-item__delete"
                  disabled={busyId === project.id}
                  onClick={() => void handleDeleteForever(project)}
                >
                  Удалить навсегда
                </button>
              </div>
              {rowErrors[project.id] && <p className="archive-item__error">{rowErrors[project.id]}</p>}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
