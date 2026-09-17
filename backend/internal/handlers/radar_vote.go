package handlers

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"regexp"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"

	"github.com/pedrolucas201/truck-router/backend/internal/middleware"
)

// Voto de motorista sobre um radar: existe ou não, e qual o limite.
//
// Por que no servidor e não no app (decisão do Pedro, 17/09/2026): o objetivo
// declarado é a maioria valer PRA TODOS e barrar voto de má-fé. Contagem feita
// no celular não resiste a isso — app modificado escreveria o placar que
// quisesse. Aqui o cliente só manda a própria opinião; quem conta é o servidor.
//
// Antes disto o override era um `set()` num doc por radar: o último a votar
// apagava os outros e ninguém ficava sabendo que houve discordância. Beto
// dizendo 80 e Fernando 90 nunca convergiam — cada um via o seu pra sempre.
const (
	// Abaixo disto a maioria não manda: com 1 ou 2 votos cada motorista segue
	// com o próprio (é o que o override local do app já faz). Escolha do Pedro
	// entre 1, 3 e 5.
	// ponytail: constante calibrada, e o teto é social, não técnico. Com 10
	// motoristas 3 pode ser pouco; reavaliar quando o evento `vote` mostrar
	// quantos de fato votam no MESMO radar.
	votoPisoMaioria = 3
	votoKmhMax      = 130 // acima disso não é placa, é dedo errado
	votosCol        = "radar_votes"
	overridesCol    = "radar_overrides"
)

// O `rid` vem PRONTO do app (dismissalKey: lat_lng com 5 casas) em vez de ser
// recalculado aqui. Refazer a formatação em Go abriria a chance de a 5ª casa
// arredondar diferente do Dart e o voto não casar com o radar — a chave tem que
// ser byte a byte a mesma dos dois lados. Aqui só o FORMATO é validado.
// Latitude tem no máximo 2 dígitos antes do ponto (90), longitude 3 (180).
var ridRe = regexp.MustCompile(`^-?\d{1,2}\.\d{5}_-?\d{1,3}\.\d{5}$`)

type Votos struct {
	fs *firestore.Client
}

func NewVotos(c *firestore.Client) *Votos { return &Votos{fs: c} }

type votoIn struct {
	Rid    string  `json:"rid"`
	Lat    float64 `json:"lat"`
	Lng    float64 `json:"lng"`
	Exists bool    `json:"exists"`
	Kmh    int     `json:"kmh"` // 0 = não opinou sobre o limite
}

// voto é o que UM motorista disse. Um por (radar, uid).
type voto struct {
	Exists bool
	Kmh    int
}

// placar é o que o servidor publica pro app.
type placar struct {
	N           int  `json:"n"`
	Exists      bool `json:"exists"`
	Kmh         int  `json:"kmh"`
	MandaExists bool `json:"mandaExists"`
	MandaKmh    bool `json:"mandaKmh"`
}

// decidirVotos é PURA de propósito: é a regra que o Pedro escolheu e a única
// coisa deste arquivo que precisa de teste. As duas perguntas são
// independentes — dá pra ter maioria sobre "existe" e empate sobre o limite.
//
// Menos de [votoPisoMaioria] votos: ninguém manda, cada um vê o seu. Com o piso
// atingido, maioria SIMPLES manda pra todos, inclusive pra quem discordou.
// Empate não muda nada: o asset só tem limite oficial em 5,5% dos radares
// (medido em 17/09), então não serve de fiel da balança.
func decidirVotos(vs []voto) placar {
	p := placar{N: len(vs)}
	if len(vs) == 0 {
		return p
	}

	// "Existe?" — todos opinam.
	sim, nao := 0, 0
	for _, v := range vs {
		if v.Exists {
			sim++
		} else {
			nao++
		}
	}
	p.MandaExists = len(vs) >= votoPisoMaioria && sim != nao
	// Sem maioria, o resultado publicado é NEUTRO (`true`), não o placar cru.
	// O doc agregado é lido também pelo app ANTIGO, que não conhece
	// `mandaExists` e aplica `exists` direto: publicar `false` sem maioria
	// faria o radar SUMIR pra todo mundo por voto de um — e radar que não toca
	// é multa.
	p.Exists = !p.MandaExists || sim > nao

	// "Qual o limite?" — só entre quem diz que existe E deu número. Quem vota
	// "não existe" não tem opinião sobre a placa.
	porKmh := map[int]int{}
	comKmh := 0
	for _, v := range vs {
		if v.Exists && v.Kmh > 0 {
			porKmh[v.Kmh]++
			comKmh++
		}
	}
	melhor, melhorN, empatado := 0, 0, false
	for kmh, n := range porKmh {
		switch {
		case n > melhorN:
			melhor, melhorN, empatado = kmh, n, false
		case n == melhorN:
			empatado = true
		}
	}
	p.MandaKmh = comKmh >= votoPisoMaioria && melhorN > 0 && !empatado
	// Mesmo motivo do `exists`: sem maioria publica 0, que o app (novo e antigo)
	// lê como "não mexe no limite". Publicar o mais votado sem piso deixaria um
	// voto isolado trocando o limite pra todos na versão antiga.
	if p.MandaKmh {
		p.Kmh = melhor
	}
	return p
}

func (h *Votos) Create(w http.ResponseWriter, r *http.Request) {
	uid := middleware.UIDFromContext(r.Context())
	var in votoIn
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		sosErr(w, http.StatusBadRequest, "body", nil)
		return
	}
	if !ridRe.MatchString(in.Rid) {
		sosErr(w, http.StatusBadRequest, "rid", nil)
		return
	}
	if in.Lat < -90 || in.Lat > 90 || in.Lng < -180 || in.Lng > 180 ||
		(in.Lat == 0 && in.Lng == 0) {
		sosErr(w, http.StatusBadRequest, "posicao", nil)
		return
	}
	if in.Kmh < 0 || in.Kmh > votoKmhMax {
		sosErr(w, http.StatusBadRequest, "kmh", nil)
		return
	}

	ctx := r.Context()

	// UM voto por motorista: id determinístico, então revotar CORRIGE em vez de
	// somar. Sem isto, contar votos pioraria a má-fé que a maioria quer barrar.
	if _, err := h.fs.Collection(votosCol).Doc(in.Rid+"__"+uid).Set(ctx, map[string]any{
		"rid":    in.Rid,
		"uid":    uid,
		"lat":    in.Lat,
		"lng":    in.Lng,
		"exists": in.Exists,
		"kmh":    in.Kmh,
		"at":     time.Now(),
	}); err != nil {
		log.Printf("voto %s: set: %v", in.Rid, err)
		sosErr(w, http.StatusInternalServerError, "interno", nil)
		return
	}

	// Recalcula do ZERO em vez de ajustar contador por delta: com uma dezena de
	// motoristas são poucas leituras, e estado derivado que se auto-corrige não
	// acumula erro de contagem.
	vs, err := h.lerVotos(ctx, in.Rid)
	if err != nil {
		log.Printf("voto %s: ler: %v", in.Rid, err)
		sosErr(w, http.StatusInternalServerError, "interno", nil)
		return
	}
	p := decidirVotos(vs)

	// O agregado mantém `exists`/`speedKmh` com os MESMOS nomes de antes: é o
	// que o app já lê, então a versão anterior continua funcionando igual.
	if _, err := h.fs.Collection(overridesCol).Doc(in.Rid).Set(ctx, map[string]any{
		"lat":         in.Lat,
		"lng":         in.Lng,
		"exists":      p.Exists,
		"speedKmh":    p.Kmh,
		"n":           p.N,
		"mandaExists": p.MandaExists,
		"mandaKmh":    p.MandaKmh,
		"updatedAt":   time.Now(),
	}); err != nil {
		log.Printf("voto %s: agregar: %v", in.Rid, err)
		sosErr(w, http.StatusInternalServerError, "interno", nil)
		return
	}

	log.Printf("voto %s uid=%s exists=%v kmh=%d -> n=%d mandaExists=%v mandaKmh=%v kmh=%d",
		in.Rid, uid, in.Exists, in.Kmh, p.N, p.MandaExists, p.MandaKmh, p.Kmh)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(p)
}

func (h *Votos) lerVotos(ctx context.Context, rid string) ([]voto, error) {
	it := h.fs.Collection(votosCol).Where("rid", "==", rid).Documents(ctx)
	defer it.Stop()
	var out []voto
	for {
		doc, err := it.Next()
		if err == iterator.Done {
			return out, nil
		}
		if err != nil {
			return nil, err
		}
		d := doc.Data()
		ex, _ := d["exists"].(bool)
		kmh, _ := d["kmh"].(int64)
		out = append(out, voto{Exists: ex, Kmh: int(kmh)})
	}
}
