import { useEffect, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { api, ApiError } from "../lib/api";
import type { Note, Project, Task } from "../lib/types";
import { TaskList } from "../components/TaskList";
import { NoteList } from "../components/NoteList";
import "./ProjectDetailPage.css";

type LoadState = "loading" | "ready" | "not-found" | "error";

export function ProjectDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const [project, setProject] = useState<Project | null>(null);
  const [tasks, setTasks] = useState<Task[] | null>(null);
  const [notes, setNotes] = useState<Note[] | null>(null);
  const [loadState, setLoadState] = useState<LoadState>("loading");
  const [archiving, setArchiving] = useState(false);
  const [archiveError, setArchiveError] = useState<string | null>(null);

  useEffect(() => {
    if (!id) return;
    let cancelled = false;

    async function load() {
      try {
        const [fetchedProject, fetchedTasks, fetchedNotes] = await Promise.all([
          api.get<Project>(`/projects/${id}`),
          api.get<Task[]>(`/projects/${id}/tasks`),
          api.get<Note[]>(`/projects/${id}/notes`),
        ]);
        if (cancelled) return;
        setProject(fetchedProject);
        setTasks(fetchedTasks);
        setNotes(fetchedNotes);
        setLoadState("ready");
      } catch (err) {
        if (cancelled) return;
        // A 401 here already triggered the global redirect to /login.
        if (err instanceof ApiError && err.status === 401) return;
        setLoadState(err instanceof ApiError && err.status === 404 ? "not-found" : "error");
      }
    }

    void load();
    return () => {
      cancelled = true;
    };
  }, [id]);

  async function handleArchive() {
    if (!project) return;
    setArchiving(true);
    setArchiveError(null);
    try {
      await api.post(`/projects/${project.id}/archive`);
      // Archiving drops the project off the default board, and this page
      // doesn't have its own "archived" UI to fall back into -- staying here
      // would just look like nothing happened, so head back to the board.
      navigate("/", { replace: true });
    } catch {
      setArchiveError("Не удалось архивировать проект.");
      setArchiving(false);
    }
  }

  return (
    <div className="project-detail-page">
      <Link to="/" className="project-detail-page__back">
        ← Доска
      </Link>

      {loadState === "loading" && <p className="project-detail-page__note">Загрузка…</p>}
      {loadState === "not-found" && <p className="project-detail-page__note">Проект не найден.</p>}
      {loadState === "error" && (
        <p className="project-detail-page__error">Не удалось загрузить проект. Попробуйте обновить страницу.</p>
      )}

      {loadState === "ready" && project && tasks && notes && (
        <>
          <div className="project-detail-page__header">
            <h1 className="project-detail-page__title">{project.name}</h1>
            <button
              type="button"
              className="project-detail-page__archive"
              onClick={() => void handleArchive()}
              disabled={archiving}
            >
              Архивировать
            </button>
          </div>

          {archiveError && <p className="project-detail-page__error project-detail-page__error--inline">{archiveError}</p>}

          <div className="project-detail-page__body">
            <section className="project-detail-page__section">
              <h2>Задачи</h2>
              <TaskList projectId={project.id} tasks={tasks} onTasksChange={setTasks} />
            </section>

            <section className="project-detail-page__section">
              <h2>Заметки</h2>
              <NoteList projectId={project.id} notes={notes} onNotesChange={setNotes} />
            </section>
          </div>
        </>
      )}
    </div>
  );
}
