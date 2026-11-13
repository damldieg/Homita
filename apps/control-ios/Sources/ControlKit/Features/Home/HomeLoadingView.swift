import SwiftUI
#if canImport(ComponentsKit)
import ComponentsKit
#endif

/// Carga inicial: esqueleto con la misma forma que la pestaña Inicio (cabecera, Eventos, Tareas,
/// Rutinas de hoy y accesos rápidos). Sin spinner ni texto; solo bloques en brillo.
struct HomeLoadingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Cabecera: saludo y fecha, con el botón ⌂ a la derecha.
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    HomitaSkeletonBlock(height: 34)
                        .frame(maxWidth: 260)
                    HomitaSkeletonBlock(height: 16)
                        .frame(maxWidth: 180)
                }
                Spacer(minLength: Spacing.s3)
                HomitaSkeletonBlock(height: 44)
                    .frame(width: 44)
            }
            .padding(.top, Spacing.s2)

            // Hoy · Eventos
            skeletonCard {
                cardHeader()
                ForEach(0..<2, id: \.self) { _ in
                    HStack(spacing: 12) {
                        HomitaSkeletonBlock(height: 36)
                            .frame(width: 4)
                        VStack(alignment: .leading, spacing: 6) {
                            HomitaSkeletonBlock(height: 16).frame(maxWidth: 200)
                            HomitaSkeletonBlock(height: 12).frame(maxWidth: 110)
                        }
                        Spacer(minLength: Spacing.s3)
                        HomitaSkeletonBlock(height: 16).frame(width: 52)
                    }
                }
            }

            // Tareas pendientes: puntos de página, lista y casillas.
            skeletonCard {
                cardHeader()
                HStack(spacing: 8) {
                    Spacer()
                    HomitaSkeletonBlock(height: 8).frame(width: 8)
                    HomitaSkeletonBlock(height: 8).frame(width: 8)
                    Spacer()
                }
                HomitaSkeletonBlock(height: 14).frame(maxWidth: 120)
                ForEach(0..<4, id: \.self) { _ in
                    HStack(spacing: 12) {
                        HomitaSkeletonBlock(height: 22).frame(width: 22)
                        HomitaSkeletonBlock(height: 16).frame(maxWidth: 180)
                        Spacer(minLength: 0)
                    }
                }
            }

            // Rutinas de hoy: progreso, barra y dos filas.
            skeletonCard {
                cardHeader()
                HomitaSkeletonBlock(height: 14).frame(maxWidth: 160)
                HomitaSkeletonBlock(height: 8)
                ForEach(0..<2, id: \.self) { _ in
                    HomitaSkeletonBlock(height: 56)
                }
            }

            // Accesos rápidos: título y dos botones.
            HomitaSkeletonBlock(height: 14)
                .frame(maxWidth: 140)
            HStack(spacing: 12) {
                HomitaSkeletonBlock(height: 50)
                HomitaSkeletonBlock(height: 50)
            }
        }
        .padding(Spacing.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.background.ignoresSafeArea())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cargando inicio")
    }

    /// Tarjeta con el mismo borde y radio que las de Inicio.
    private func skeletonCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.line, lineWidth: 1))
    }

    /// Cabecera de tarjeta: icono, título y contador.
    private func cardHeader() -> some View {
        HStack(spacing: 8) {
            HomitaSkeletonBlock(height: 36)
                .frame(width: 36)
            HomitaSkeletonBlock(height: 20)
                .frame(maxWidth: 170)
            Spacer(minLength: 0)
            HomitaSkeletonBlock(height: 22)
                .frame(width: 32)
        }
    }
}

/// Fallo al resolver el hogar, con reintento.
struct HomeErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HomitaPanel("No se pudo cargar tu hogar", systemImage: "exclamationmark.triangle", tint: Palette.accent) {
            Text(message)
                .font(HomitaFont.inter(15, relativeTo: .body))
                .foregroundStyle(Palette.inkSoft)
            HomitaButton(title: "Reintentar", action: retry)
        }
    }
}
