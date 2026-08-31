import { Link } from "react-router-dom";
import type { Project, Task } from "../lib/types";
import { TaskRow } from "./TaskRow";
import "./ProjectColumn.css";

interface ProjectColumnProps {
  project: Project;
  /** undefined while the project's tasks are still loading. */
  tasks: Task[] | undefined;
  /** true if the tasks fetch for this project failed. */
  failed: boolean;
}

export function ProjectColumn({ project, tasks, failed }: ProjectColumnProps) {
  return (
    <section className="project-column">
      <h2 className="project-column__title">
        <Link to={`/projects/${project.id}`} title={project.name}>
          {project.name}
        </Link>
      </h2>

      {failed && <p className="project-column__note">не удалось загрузить задачи</p>}
      {!failed && tasks === undefined && <p className="project-column__note">загрузка…</p>}
      {!failed && tasks !== undefined && tasks.length === 0 && (
        <p className="project-column__note">нет задач</p>
      )}
      {!failed && tasks !== undefined && tasks.length > 0 && (
        <div className="project-column__tasks">
          {tasks.map((task) => (
            <TaskRow key={task.id} task={task} />
          ))}
        </div>
      )}
    </section>
  );
}
