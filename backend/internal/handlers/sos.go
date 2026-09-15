package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"time"
	"unicode/utf8"

	"cloud.google.com/go/firestore"
	"github.com/go-chi/chi/v5"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/pedrolucas201/truck-router/backend/internal/middleware"
)

// S.O.S. entre motoristas (docs/sos-rede-motoristas.md). O app NÃO escreve em
// `sos` direto: os gates abaixo só valem se ninguém puder pular.
//
// Gates do Create: perfil com nome+telefone, conta Google vinculada, conta com
// >= 24 h (mínimo grátis contra S.O.S.-isca de conta recém-criada), um aberto
// por uid. Telefone NUNCA entra no doc `sos`: só em `sos/{id}/contatos/{uid}`,
// escrito no aceite, um doc por lado, legível só pelo próprio uid.

const (
	sosTTL         = 2 * time.Hour
	sosPerfilIdade = 24 * time.Hour // ponytail: constante calibrada; sobe se aparecer isca
	sosTextoMax    = 120
)

var sosTipos = map[string]bool{
	"ferramenta": true, "pneu": true, "combustivel": true, "mecanica": true,
	"reboque": true, "saude": true, "outro": true,
}

type Sos struct {
	fs *firestore.Client
}

func NewSos(c *firestore.Client) *Sos { return &Sos{fs: c} }

type sosCreateIn struct {
	Lat   float64 `json:"lat"`
	Lng   float64 `json:"lng"`
	Tipo  string  `json:"tipo"`
	Texto string  `json:"texto"`
}

// validateSos é pura pra ser testável sem Firestore.
func validateSos(in sosCreateIn) error {
	if in.Lat < -90 || in.Lat > 90 || in.Lng < -180 || in.Lng > 180 || (in.Lat == 0 && in.Lng == 0) {
		return errors.New("posicao")
	}
	if !sosTipos[in.Tipo] {
		return errors.New("tipo")
	}
	if utf8.RuneCountInString(in.Texto) > sosTextoMax {
		return errors.New("texto")
	}
	return nil
}

// sosErr responde {"error": key}; o app mapeia a chave pra mensagem. Nunca
// vaza texto de sistema (regra do Márcio).
func sosErr(w http.ResponseWriter, code int, key string, extra map[string]any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	body := map[string]any{"error": key}
	for k, v := range extra {
		body[k] = v
	}
	json.NewEncoder(w).Encode(body)
}

type perfil struct {
	Nome, Caminhao, Cor, Telefone string
}

func (h *Sos) perfil(r *http.Request, uid string) (perfil, bool) {
	doc, err := h.fs.Collection("profiles").Doc(uid).Get(r.Context())
	if err != nil {
		return perfil{}, false
	}
	d := doc.Data()
	str := func(k string) string { s, _ := d[k].(string); return s }
	p := perfil{Nome: str("name"), Caminhao: str("truck"), Cor: str("color"), Telefone: str("phone")}
	return p, p.Nome != "" && p.Telefone != ""
}

func (h *Sos) Create(w http.ResponseWriter, r *http.Request) {
	uid := middleware.UIDFromContext(r.Context())
	var in sosCreateIn
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		sosErr(w, http.StatusBadRequest, "body", nil)
		return
	}
	if err := validateSos(in); err != nil {
		sosErr(w, http.StatusBadRequest, err.Error(), nil)
		return
	}
	p, ok := h.perfil(r, uid)
	if !ok {
		sosErr(w, http.StatusPreconditionFailed, "perfil", nil)
		return
	}

	// Conta: Google vinculada e com idade mínima. O cliente não consegue
	// forjar nenhum dos dois.
	u, err := middleware.AuthClient().GetUser(r.Context(), uid)
	if err != nil {
		log.Printf("sos create: GetUser %s: %v", uid, err)
		sosErr(w, http.StatusInternalServerError, "interno", nil)
		return
	}
	google := false
	for _, pi := range u.ProviderUserInfo {
		if pi.ProviderID == "google.com" {
			google = true
		}
	}
	if !google {
		sosErr(w, http.StatusPreconditionFailed, "google", nil)
		return
	}
	criada := time.UnixMilli(u.UserMetadata.CreationTimestamp)
	if libera := criada.Add(sosPerfilIdade); time.Now().Before(libera) {
		sosErr(w, http.StatusPreconditionFailed, "conta_nova",
			map[string]any{"liberaEm": libera.UTC().Format(time.RFC3339)})
		return
	}

	// Um aberto por uid. Só igualdade (uid, status) — sem range, sem índice
	// composto. Expirado-mas-ainda-aberto é fechado aqui mesmo.
	now := time.Now()
	col := h.fs.Collection("sos")
	it := col.Where("uid", "==", uid).Where("status", "==", "aberto").Limit(1).Documents(r.Context())
	if doc, err := it.Next(); err == nil {
		if exp, _ := doc.Data()["expireAt"].(time.Time); exp.After(now) {
			sosErr(w, http.StatusConflict, "ja_aberto", map[string]any{"id": doc.Ref.ID})
			return
		}
		_, _ = doc.Ref.Update(r.Context(), []firestore.Update{{Path: "status", Value: "expirado"}})
	}
	it.Stop()

	ref, _, err := col.Add(r.Context(), map[string]any{
		"uid":      uid,
		"nome":     p.Nome,
		"caminhao": p.Caminhao,
		"cor":      p.Cor,
		"tipo":     in.Tipo,
		"texto":    in.Texto,
		"lat":      in.Lat,
		"lng":      in.Lng,
		"status":   "aberto",
		"criadoEm": now,
		"expireAt": now.Add(sosTTL),
	})
	if err != nil {
		log.Printf("sos create: add: %v", err)
		sosErr(w, http.StatusInternalServerError, "interno", nil)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]any{"id": ref.ID})
}

func (h *Sos) Aceitar(w http.ResponseWriter, r *http.Request) {
	uid := middleware.UIDFromContext(r.Context())
	id := chi.URLParam(r, "id")
	if id == "" {
		sosErr(w, http.StatusBadRequest, "id", nil)
		return
	}
	ajudante, ok := h.perfil(r, uid)
	if !ok {
		sosErr(w, http.StatusPreconditionFailed, "perfil", nil)
		return
	}
	ref := h.fs.Collection("sos").Doc(id)

	// Leituras antes das escritas (exigência da transação do Firestore).
	snap, err := ref.Get(r.Context())
	if status.Code(err) == codes.NotFound {
		sosErr(w, http.StatusNotFound, "nao_existe", nil)
		return
	}
	if err != nil {
		log.Printf("sos aceitar: get %s: %v", id, err)
		sosErr(w, http.StatusInternalServerError, "interno", nil)
		return
	}
	pedinteUID, _ := snap.Data()["uid"].(string)
	if pedinteUID == uid {
		sosErr(w, http.StatusBadRequest, "proprio", nil)
		return
	}
	pedinte, ok := h.perfil(r, pedinteUID)
	if !ok {
		sosErr(w, http.StatusConflict, "sem_contato", nil)
		return
	}

	now := time.Now()
	err = h.fs.RunTransaction(r.Context(), func(_ context.Context, tx *firestore.Transaction) error {
		cur, err := tx.Get(ref)
		if err != nil {
			return err
		}
		d := cur.Data()
		if st, _ := d["status"].(string); st != "aberto" {
			return errSosStatus(st)
		}
		if exp, _ := d["expireAt"].(time.Time); !exp.After(now) {
			return errSosStatus("expirado")
		}
		if err := tx.Update(ref, []firestore.Update{
			{Path: "status", Value: "atendendo"},
			{Path: "ajudanteUid", Value: uid},
			{Path: "ajudanteNome", Value: ajudante.Nome},
			{Path: "aceitoEm", Value: now},
		}); err != nil {
			return err
		}
		// Cada lado lê SÓ o próprio doc (regra). O telefone do outro fica aqui,
		// nunca no doc principal.
		if err := tx.Set(ref.Collection("contatos").Doc(pedinteUID), map[string]any{
			"uid": uid, "nome": ajudante.Nome, "telefone": ajudante.Telefone,
		}); err != nil {
			return err
		}
		return tx.Set(ref.Collection("contatos").Doc(uid), map[string]any{
			"uid": pedinteUID, "nome": pedinte.Nome, "telefone": pedinte.Telefone,
		})
	})
	var se sosStatusErr
	if errors.As(err, &se) {
		sosErr(w, http.StatusConflict, string(se), nil)
		return
	}
	if err != nil {
		log.Printf("sos aceitar: tx %s: %v", id, err)
		sosErr(w, http.StatusInternalServerError, "interno", nil)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{"nome": pedinte.Nome, "telefone": pedinte.Telefone})
}

type sosStatusErr string

func (e sosStatusErr) Error() string { return string(e) }
func errSosStatus(s string) error    { return sosStatusErr(s) }
