:- module(servidor_unacar, [iniciar_servidor/1, detener_servidor/1]).

% Librerias de SWI-Prolog para el servidor HTTP y JSON
:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_json)).
:- use_module(library(http/http_cors)).
:- use_module(library(http/http_parameters)).

% Habilitar CORS para permitir peticiones desde cualquier origen
:- set_setting(http:cors, [*]).

% =========================================================================
% 1. BASE DE CONOCIMIENTO (DATOS)
% =========================================================================

% profesor(#empleado, Nombre, GradoAcademico, Especialidad, ListaCursosDominados)
profesor(101, 'Dr. Carlos Mendoza', doctorado, 'Inteligencia Artificial', ['IA Avanzada', 'Programacion Logica', 'Estructuras de Datos']).
profesor(102, 'Mtra. Ana Gomez', maestria, 'Ingenieria de Software', ['Ingenieria de Software', 'Bases de Datos', 'Programacion Web']).
profesor(103, 'Ing. Luis Torres', licenciatura, 'Redes y Seguridad', ['Redes', 'Seguridad Informatica', 'Sistemas Operativos']).

% capacitaciones_tomadas(#empleado, ListaCursosCapacitacion)
capacitaciones_tomadas(101, ['Docencia Universitaria', 'Taller de IA']).
capacitaciones_tomadas(102, ['Gestion de Proyectos Agile']).
capacitaciones_tomadas(103, ['Redes CISCO']).

% cuerpo_academico(Id, Nombre, LineaInvestigacion, LiderId, Estatus)
cuerpo_academico(ca1, 'Sistemas Inteligentes', 'Inteligencia Aplicada', 101, consolidado).
cuerpo_academico(ca2, 'Ingenieria de Software Aplicada', 'Desarrollo Web y Movil', 102, en_consolidation).

% academia(Id, Nombre, MateriasAsignadas, LiderId)
academia(ac1, 'Ciencia de Datos e IA', ['IA Avanzada', 'Programacion Logica'], 101).
academia(ac2, 'Desarrollo de Software', ['Ingenieria de Software', 'Programacion Web'], 102).

% proyecto(Id, Nombre, Objetivo, Entregables, LiderId, Integrantes, FechaInicio, FechaEntrega)
proyecto(p1, 'Sistema Experto UNACAR', 'Automatizar asignaciones', ['Servidor Prolog', 'Manual'], 101, [102], '2026-01-15', '2026-06-30').

% curso(Id, Creditos, Nombre, Objetivo, AcademiaId)
curso(c1, 5, 'Programacion Logica', 'Aprender Prolog', ac1).
curso(c2, 6, 'Ingenieria de Software', 'Aprender metodologias agiles', ac2).

% curso_capacitacion(Id, Nombre, Objetivo, NumHoras, FechaInicio, FechaConclusion)
curso_capacitacion(cc1, 'Taller de IA', 'Capacitar en LLMs', 40, '2026-02-01', '2026-02-15').

% =========================================================================
% 2. REGLAS DE ASIGNACION Y CONSULTA
% =========================================================================

% Jerarquia de grados academicos
valor_grado(doctorado, 3).
valor_grado(maestria, 2).
valor_grado(licenciatura, 1).

% Buscar un profesor y todas sus asignaciones
buscar_profesor_completo(NumEmp, ResJSON) :-
    profesor(NumEmp, Nom, Grado, Esp, Cursos),
    capacitaciones_tomadas(NumEmp, Caps),
    findall(CA, cuerpo_academico(CA, _, _, NumEmp, _), CAsLiderados),
    findall(A, academia(A, _, _, NumEmp), AcademiasLideradas),
    findall(P, proyecto(P, _, _, _, NumEmp, _, _, _), ProyectosLiderados),
    ResJSON = json([
        num_empleado = NumEmp,
        nombre = Nom,
        grado_academico = Grado,
        especialidad = Esp,
        cursos_que_domina = Cursos,
        capacitaciones = Caps,
        cuerpos_academicos_liderados = CAsLiderados,
        academias_lideradas = AcademiasLideradas,
        proyectos_liderados = ProyectosLiderados
    ]).

% Asignar profesores a una entidad segun coincidencia en especialidad o cursos
profesores_aptos_para_area(Area, ListaProfesores) :-
    findall(json([num_empleado=Id, nombre=Nom, grado=Grado, especialidad=Esp]),
            (profesor(Id, Nom, Grado, Esp, Cursos),
             (Esp = Area ; member(Area, Cursos))),
            ListaProfesores).

% Seleccionar el mejor profesor para un curso (mayor grado academico)
mejor_profesor_para_curso(NombreCurso, ProfesorInfo) :-
    curso(_, _, NombreCurso, _, _),
    findall(prof(Valor, Id, Nom, Grado, Esp),
            (profesor(Id, Nom, Grado, Esp, Cursos),
             member(NombreCurso, Cursos),
             valor_grado(Grado, Valor)),
            ListaCandidatos),
    sort(1, @>=, ListaCandidatos, [prof(_, Id, Nom, Grado, Esp)|_]),
    ProfesorInfo = json([num_empleado=Id, nombre=Nom, grado=Grado, especialidad=Esp]).

% =========================================================================
% 3. ENDPOINTS / HANDLERS HTTP
% =========================================================================

:- http_handler(root(api/profesor), handle_buscar_profesor, []).
:- http_handler(root(api/asignar/area), handle_profesores_area, []).
:- http_handler(root(api/asignar/curso), handle_mejor_profesor_curso, []).

handle_buscar_profesor(Request) :-
    cors_enable,
    http_parameters(Request, [id(NumEmp, [integer])]),
    (   buscar_profesor_completo(NumEmp, ResJSON)
    ->  reply_json(ResJSON)
    ;   reply_json(json([error='Profesor no encontrado']), [status(404)])
    ).

handle_profesores_area(Request) :-
    cors_enable,
    http_parameters(Request, [area(Area, [atom])]),
    profesores_aptos_para_area(Area, Lista),
    reply_json(json([area=Area, candidatos_aptos=Lista])).

handle_mejor_profesor_curso(Request) :-
    cors_enable,
    http_parameters(Request, [curso(NombreCurso, [atom])]),
    (   mejor_profesor_para_curso(NombreCurso, ProfJSON)
    ->  reply_json(json([curso=NombreCurso, mejor_candidato=ProfJSON]))
    ;   reply_json(json([error='No se encontro un profesor capacitado']), [status(404)])
    ).

% =========================================================================
% 4. COMANDOS DE INICIO/PARO DEL SERVIDOR
% =========================================================================

iniciar_servidor(Puerto) :-
    http_server(http_dispatch, [port(Puerto)]),
    format('Servidor Prolog activo en http://localhost:~w/~n', [Puerto]).

detener_servidor(Puerto) :-
    http_stop_server(Puerto, []).