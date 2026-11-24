#  TSR Builders – Construction Management Platform

A modern, web-based Construction Management System designed to simplify construction site operations, workforce coordination, supervisor management and inventory tracking.

The platform aims to bring essential construction management activities into one centralized application, helping administrators, project managers and site supervisors manage their responsibilities efficiently.

---

## Project Overview

TSR Builders is a construction management application developed to improve the way construction projects and site activities are managed.

The system provides role-based access to different users and supports centralized management of construction sites, supervisors, workforce and inventory-related operations.

The goal is to reduce manual coordination, improve visibility across projects and make day-to-day site management more organized.

##  Key Features

### Site Management
- Centralized construction site management.
- View and manage active construction sites.
- Organize site-related information and assignments.
- Monitor site operational status.

### Supervisor Management
- Create and manage supervisor accounts.
- Assign supervisors to construction sites.
- Manage supervisor assignments across multiple sites.
- Activate and deactivate site assignments.
- Role-based access to supervisor management functions.

### Workforce Management
- Workforce-related management workflows.
- Attendance and workforce tracking capabilities.
- Support for site-level workforce coordination.

### Inventory Management
- Construction material and inventory management workflows.
- Support for organizing stock-related information.
- Designed to improve visibility into site materials.

### Role-Based Access Control
The application is designed around different user roles:

- **Administrator** – Overall application and user management.
- **Project Manager** – Project and site-related management.
- **Supervisor** – Assigned site operations and relevant workflows.

Access to application features is controlled through authentication and authorization.

### Responsive Application
- Responsive user interface.
- Designed for desktop and mobile-sized screens.
- Progressive Web App (PWA) capabilities.

---

## Technology Stack

| Technology | Purpose |
|---|---|
| Next.js 15 | Web application framework |
| React | User interface |
| TypeScript | Type-safe development |
| Tailwind CSS | Styling and responsive design |
| Supabase | Backend services and database |
| PostgreSQL | Relational database |
| Supabase Auth | User authentication |
| Row Level Security (RLS) | Database access protection |

---

## 🏛️ Application Architecture

The application follows a modern web application architecture.

```text
       User / Browser
              |
              v
      Next.js Web Application
              |
              v
        Supabase Backend
          /          \
         v            v
 Authentication   PostgreSQL
                      |
                      v
               Row Level Security
```

The application uses authenticated access and database-level security policies to protect application data.

---


## 🎬 Project Demo

A demonstration video and live preview can be added here when available.

- **Live Demo:** Coming soon
- **Demo Video:** Coming soon

*The public demonstration will use sample data and a dedicated test environment.*

---

## 🔒 Security & Data Protection

Security and controlled access are important parts of this application.

- Authentication-based access.
- Role-based authorization.
- Supabase Row Level Security (RLS).
- Server-side handling of privileged operations.
- Restricted access to sensitive management functions.

No production credentials, private employee information or confidential company records are included in this public showcase.

---

##  Future Enhancements

- Further improvements to construction site management.
- Expanded workforce and attendance workflows.
- Enhanced inventory management.
- Additional reporting and analytics.
- Dedicated mobile application using React Native / Expo.
- Further automated and integration testing.

---

## Project Status

**Status:** Actively Under Development

This project is being developed and improved continuously. Features and workflows may evolve as development progresses.

---

##  Development

**Organization:** TSR Builders  
**Project:** Construction Management Platform

---

## License

This repository is a project showcase. All rights to the application, branding, design and associated materials remain with their respective owners.

Unauthorized copying, redistribution or commercial use is not permitted without permission.
